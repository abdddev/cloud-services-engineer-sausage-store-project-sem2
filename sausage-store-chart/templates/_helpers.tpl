{{/*
Базовый init-контейнер, который логинится в Vault по токену.
Сама команда (что именно достать из Vault и куда положить) задаётся
в `command:` на стороне вызывающего шаблона ДО include этого хелпера.
*/}}
{{- define "vault.init.container" }}
name: vault-secrets
image: {{ .Values.global.vault.image }}
imagePullPolicy: {{ .Values.global.imagePullPolicy }}
env:
  - name: VAULT_ADDR
    value: {{ .Values.global.vault.addr | quote }}
  - name: VAULT_TOKEN
    value: {{ .Values.global.vault.token | quote }}
{{- with .Values.global.vault.resources.container }}
resources:
  {{ toYaml . | nindent 2 }}
{{- end }}
volumeMounts:
  - name: {{ .Values.global.vault.volume }}
    mountPath: {{ .Values.global.secrets }}
{{- end }}
