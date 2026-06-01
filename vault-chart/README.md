# Чарт `vault-chart`

Одно-нодовый HashiCorp Vault (file storage, dev-подобный, но с PVC).
Ставится **отдельным релизом** в тот же namespace, что и `sausage-store`.

## 1. Установка

```bash
export KUBECONFIG=/home/alexanderdb/.kube/sausage-store-config
NS=r-devops-magistracy-project-2sem-792101529

helm upgrade --install vault ./vault-chart -n "$NS"
kubectl -n "$NS" rollout status deploy/vault
```

## 2. Инициализация и unseal

Vault после старта **запечатан (sealed)** — это нормально. Инициализируем один раз:

```bash
kubectl -n "$NS" exec -it deploy/vault -- sh

# внутри пода:
vault operator init          # СОХРАНИТЕ 5 Unseal Key и Initial Root Token!
vault operator unseal        # ввести 3 раза, по одному из 3 разных Unseal Key
vault login                  # вставить Initial Root Token
vault secrets enable -path=kv kv-v2
```

> ⚠️ После **каждого** рестарта пода Vault его нужно снова `unseal` (3 ключа).
> Пока Vault sealed — init-контейнеры postgres/mongo/backend-report висят в ожидании.

## 3. Заполнение секретов

```sh
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

| Ключ | Кто читает |
|---|---|
| `spring.datasource.*` | backend (spring-cloud-vault), postgres init-контейнер (`_FILE`) |
| `postgresql.init.database` | postgres init-контейнер → `POSTGRES_DB_FILE` |
| `mongodb.init.username/password` | mongo init-контейнер (`_FILE`), mongo-init Job, backend health-check |
| `spring.data.mongodb.{host,port,database,username,password}` | backend-report (init-контейнер строит `DB`), mongo-init Job (создаёт юзера) |
| `spring.data.mongodb.uri` | backend (health-check Mongo через spring-cloud-vault) |

## 4. Политика и токен для приложения

```sh
vault policy write sausage-store-read - <<EOF
path "kv/data/sausage-store" {
  capabilities = ["read"]
}
EOF

vault token create -policy=sausage-store-read -ttl=768h
```

Полученный `token` положить в **GitHub Secret `VAULT_TOKEN`** — CI прокидывает его
в релиз через `--set global.vault.token=...`.

## 5. Проверка UI (опционально)

```bash
kubectl -n "$NS" port-forward deploy/vault 8200:8200
# http://localhost:8200/ui/
```
