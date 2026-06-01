# Vault — что и как запускать

Доп. задание: все секреты приложения вынесены в **HashiCorp Vault**.
Ни в `values.yaml`, ни в `application.properties`, ни в манифестах кредов больше нет.

## Архитектура секретов

```
                    ┌────────────────────────────┐
                    │           Vault            │  kv/sausage-store
                    │  (vault-chart, отдельно)   │
                    └──────────────┬─────────────┘
            token (из CI)          │  vault kv get ...
        ┌──────────────────────────┼──────────────────────────────┐
        │                          │                              │
  backend (spring-cloud-vault)   init-контейнеры            init-контейнер
  читает напрямую:               postgres / mongo:          backend-report:
   spring.datasource.*           пишут креды в файлы →        пишет DB=... →
   spring.data.mongodb.uri        POSTGRES_*_FILE /            основной контейнер
                                  MONGO_INITDB_*_FILE          сорсит файл в env
```

| Компонент | Как получает секреты |
|---|---|
| **backend** | `spring-cloud-vault` по токену: `SPRING_CONFIG_IMPORT=vault://kv/sausage-store` |
| **postgresql** | vault-init-контейнер → файлы → `POSTGRES_USER_FILE/PASSWORD_FILE/DB_FILE` |
| **mongodb** | vault-init-контейнер → файлы → `MONGO_INITDB_ROOT_USERNAME_FILE/PASSWORD_FILE` |
| **mongodb-init Job** | vault-init-контейнер → создаёт прикладного юзера `reporter` |
| **backend-report** | vault-init-контейнер строит `DB=mongodb://...`, контейнер сорсит его в env |

Токен Vault приходит в релиз из CI: `--set global.vault.token=$VAULT_TOKEN`
и кладётся в Secret `*-backend-vault-token` (для backend) / env init-контейнеров.

---

## Шаги запуска (по порядку)

### 0. Окружение

```bash
export KUBECONFIG=/home/alexanderdb/.kube/sausage-store-config
export NS=r-devops-magistracy-project-2sem-792101529
```

### 1. Установить Vault (отдельный релиз)

```bash
helm upgrade --install vault ./vault-chart -n "$NS"
kubectl -n "$NS" rollout status deploy/vault
```

> ⚠️ Квота кластера `services=5`. Поэтому у `backend-report` **убран Service**
> (его никто не вызывает по DNS), и слот освобождён под `vault`. Итог: 5 сервисов —
> frontend, backend, postgresql, mongodb, vault.

### 2. Инициализировать и распечатать (unseal) Vault

Один раз после первой установки:

```bash
kubectl -n "$NS" exec -it deploy/vault -- sh

# внутри пода:
vault operator init          # ⚠️ СОХРАНИТЬ 5 Unseal Key и Initial Root Token
vault operator unseal        # ввести 3 раза, по одному из 3 разных Unseal Key
vault login                  # вставить Initial Root Token
vault secrets enable -path=kv kv-v2
exit
```

> После **каждого** рестарта пода Vault нужно снова `vault operator unseal` (3 ключа).
> Пока Vault `sealed` — init-контейнеры postgres/mongo/backend-report ждут и поды не стартуют.

### 3. Записать секреты в Vault

```bash
kubectl -n "$NS" exec -it deploy/vault -- sh
vault login   # root token

vault kv put kv/sausage-store \
  spring.datasource.url="jdbc:postgresql://postgresql:5432/sausage-store" \
  spring.datasource.username="store" \
  spring.datasource.password="storepassword" \
  postgresql.init.database="sausage-store" \
  mongodb.init.username="root" \
  mongodb.init.password="rootpassword" \
  spring.data.mongodb.host="mongodb" \
  spring.data.mongodb.port="27017" \
  spring.data.mongodb.database="reports" \
  spring.data.mongodb.username="reporter" \
  spring.data.mongodb.password="reporterpassword" \
  spring.data.mongodb.uri="mongodb://root:rootpassword@mongodb:27017/sausage-store?authSource=admin"

vault kv get kv/sausage-store
```

### 4. Создать политику и токен для приложения

```bash
# внутри пода Vault:
vault policy write sausage-store-read - <<EOF
path "kv/data/sausage-store" {
  capabilities = ["read"]
}
EOF

vault token create -policy=sausage-store-read -ttl=768h
# скопировать поле token (hvs.XXXXXXXX)
exit
```

### 5. Положить токен в GitHub Secrets

В репозитории: **Settings → Secrets and variables → Actions** →
обновить/создать секрет `VAULT_TOKEN` = выданный на шаге 4 токен.

CI (`.github/workflows/deploy.yaml`) уже прокидывает его:
```yaml
helm upgrade --install sausage-store nexus/sausage-store \
  --set global.vault.token="$VAULT_TOKEN" ...
```

### 6. Задеплоить приложение

Либо пушем в `main` (запустится workflow), либо вручную:

```bash
helm upgrade --install sausage-store ./sausage-store-chart \
  -n "$NS" \
  --set global.vault.token="<токен из шага 4>" \
  --wait --timeout 5m
```

---

## Проверка

```bash
# 1. Vault поднят и unsealed (Sealed=false)
kubectl -n "$NS" exec deploy/vault -- vault status

# 2. Все поды Running / Job Completed
kubectl -n "$NS" get po

# 3. Секреты реально пришли из Vault (в логах init-контейнеров)
kubectl -n "$NS" logs sts/postgresql       -c vault-secrets
kubectl -n "$NS" logs deploy/sausage-store-backend-report -c vault-secrets

# 4. backend стартовал с конфигом из Vault (нет ошибок datasource)
kubectl -n "$NS" logs deploy/sausage-store-backend --tail=50

# 5. Фронтенд открывается
curl -sk https://front-${NS}.2sem.students-projects.ru | grep -c sausage
```

---

## Локальная сборка / тесты

Vault при сборке `mvn package` **не нужен**: тесты используют
`backend/src/test/resources/application.properties` с
`spring.cloud.vault.enabled=false` и H2. Активируется Vault только в кластере,
где задана переменная `SPRING_CONFIG_IMPORT=vault://kv/sausage-store`.

---

## Траблшутинг

| Симптом | Причина / решение |
|---|---|
| Поды postgres/mongo/backend-report висят в `Init:0/1` | Vault `sealed` → `vault operator unseal` (3 ключа) |
| backend падает: `Unable to connect / Vault location [...]` | не задан/протух `VAULT_TOKEN`, либо нет политики `kv/data/sausage-store` |
| init-контейнер: `permission denied` на `kv get` | токен без политики `sausage-store-read` |
| `must specify limits.cpu` при создании пода | у контейнера нет `limits.cpu` (квота кластера требует) |
| backend-report: `DB is required` | пустой результат `vault kv get` — проверь ключи `spring.data.mongodb.*` |
