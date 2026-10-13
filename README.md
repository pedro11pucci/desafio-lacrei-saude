# desafio-lacrei-saude
Repositório do desafio técnico da Lacrei Saúde

## GitHub Secrets

O workflow usa credenciais AWS salvas no GitHub Secrets para autenticar e publicar a imagem no ECR:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Essas chaves devem pertencer ao usuário IAM `lacrei-github-actions`, criado pela infra em `infra/github_actions_iam.tf`.
O provider AWS do Terraform também usa essas variáveis de ambiente automaticamente quando a infra roda no CI.

## Observabilidade

Os comandos de deploy enviados pelo SSM ficam em CloudWatch Logs no grupo `/lacrei/deploy`.
O dashboard básico fica em CloudWatch Dashboards com o nome `lacrei-api`.

Para ver logs da aplicação, use SSM para rodar `docker logs --tail 200 lacrei-api` na instância desejada.
