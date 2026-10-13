# Desafio Técnico — Lacrei Saúde

Infraestrutura e pipeline CI/CD para uma API fictícia em Node.js, com implantação em **staging** e **production** na AWS.

O projeto utiliza **Terraform** para provisionamento, **Docker** para execução da aplicação, **Amazon ECR** como registro de imagens, **GitHub Actions** para CI/CD e **AWS Systems Manager (SSM)** para executar deploys nas instâncias EC2 sem acesso SSH.

## 1. Aplicação

API Express com um endpoint de verificação:

```http
GET /status
```

Resposta esperada (`HTTP 200`):

```json
{"status":"ok"}
```

A aplicação escuta na porta **3000**. O container expõe essa porta e a EC2 publica o serviço na porta **80** (`80:3000`).

### Executar localmente

Requisitos: Docker.

```bash
docker build -t lacrei-api:local .
docker run -d --name lacrei-local -p 3000:3000 lacrei-api:local
curl --fail http://localhost:3000/status
```

Para remover o container:

```bash
docker rm -f lacrei-local
```

O `Dockerfile` usa `node:22-alpine` e define um `HEALTHCHECK` que consulta `/status`.

## 2. Arquitetura


<img width="1536" height="1024" alt="CI_CD Pipeline com Deploy AWS" src="https://github.com/user-attachments/assets/8e8f7b29-c25c-4f11-81d5-9b07522d3f5d" />


| Componente | Responsabilidade |
| --- | --- |
| Terraform | Declarar e provisionar recursos AWS |
| EC2 `staging` e `production` | Hospedar os containers Docker |
| ECR `lacrei-api` | Armazenar imagens com tags imutáveis |
| GitHub Actions CI | Validar container, construir e publicar imagem |
| GitHub Actions CD | Selecionar versão, localizar EC2 e orquestrar deploy |
| SSM | Executar comandos remotamente, sem SSH |
| CloudWatch | Logs do SSM, dashboard e alarmes de infraestrutura |
| SNS | SMS opcional ao final de um deploy bem-sucedido |


<img width="1536" height="1024" alt="AWS VPC Architecture with EC2 Monitoring" src="https://github.com/user-attachments/assets/121d0a95-55bf-4597-b783-23be22f02690" />


## 3. Setup dos ambientes AWS

### Pré-requisitos

- Conta AWS e permissões para criar os recursos descritos no Terraform;
- AWS CLI configurado localmente;
- Terraform compatível com a versão declarada em `infra/terraform.tf`;
- Repositório no GitHub com GitHub Actions habilitado.

O projeto utiliza a **VPC padrão** e subnets padrão da região `us-east-1`; é necessário que elas existam na conta.

### Provisionamento com Terraform

```bash
cd infra
terraform init
terraform plan
terraform apply
```

Se utilizar um perfil nomeado do AWS CLI:

```bash
AWS_PROFILE=seu-perfil terraform plan
AWS_PROFILE=seu-perfil terraform apply
```

O Terraform cria:

- duas instâncias **EC2 `t2.micro`**, com tags `Name=staging` e `Name=production`;
- Security Group com entrada **TCP/80** e saída liberada;
- repositório ECR `lacrei-api`, com **tags imutáveis** e varredura de imagem no push;
- IAM Role/instance profile das EC2, com acesso de leitura ao ECR e integração ao SSM;
- usuário IAM `lacrei-github-actions` e políticas de publicação/deploy/notificação;
- grupo de logs `/lacrei/deploy`, alarmes e dashboard CloudWatch.

O `user_data.sh` prepara as instâncias Ubuntu com Docker, AWS CLI, utilitários necessários e SSM Agent. O `deploy.sh` também verifica dependências antes de executar.

**Atenção:** `user_data_replace_on_change = true` está habilitado. Alterar o User Data pode causar **substituição das instâncias** no próximo `terraform apply`, mudando IDs e IPs públicos. Revise o plano antes de confirmar.

### Credenciais no GitHub

Configure em **Settings → Secrets and variables → Actions**:

| Secret | Uso |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | Credencial do usuário IAM usado pelo GitHub Actions |
| `AWS_SECRET_ACCESS_KEY` | Chave secreta correspondente |
| `SNS_PHONE_NUMBER` | Opcional; número E.164 para SMS de deploy concluído |

O Terraform cria o **usuário IAM e suas políticas**, mas o fornecimento das access keys ao GitHub Secrets deve ser realizado separadamente. Não coloque chaves no código ou no README.

As instâncias EC2 **não usam essas chaves**: elas recebem credenciais temporárias de sua IAM Role.

### Validar os ambientes

Localize os IPs atuais das instâncias pelo console EC2 ou AWS CLI depois de um deploy bem-sucedido e faça uma requisição para o endpoint status:

```bash
curl --fail http://IP_PUBLICO_STAGING/status
curl --fail http://IP_PUBLICO_PRODUCTION/status
```

Resposta esperada: `{"status":"ok"}`. Os IPs podem mudar quando o Terraform recriar instâncias.

## 4. Fluxo de CI/CD

### CI — `.github/workflows/ci.yml`

Executado em pull requests e pushes para `master`:

1. **Test:** faz build local da imagem, inicia o container, aguarda o `HEALTHCHECK` do Docker e consulta `/status`.
2. **Publish:** apenas em **push na `master`**, após sucesso dos testes, autentica na AWS, publica a imagem no ECR com tag igual ao **SHA do commit**.

O uso do SHA identifica precisamente o código associado à imagem; o ECR está configurado para não sobrescrever tags existentes.

### CD — `.github/workflows/cd.yml`

O CD é iniciado automaticamente quando o workflow **CI** termina com sucesso após um push na `master`. Também pode ser acionado manualmente com `workflow_dispatch`.

O processo:

1. Obtém a tag da imagem (SHA do CI ou `image_tag` informado manualmente);
2. Autentica na AWS com GitHub Secrets;
3. Localiza as EC2 em execução por `Name=staging` e `Name=production`, **sem fixar IDs no YAML**;
4. Aguarda as instâncias aparecerem como **Online** no SSM;
5. Envia `.github/workflows/deploy.sh` via **SSM Run Command**;
6. A EC2 faz login no ECR com sua IAM Role, executa `docker pull`, substitui o container e valida o serviço;
7. O workflow consulta o resultado das invocações SSM e **só avança para produção após a etapa de staging concluir com sucesso**;
8. Opcionalmente, publica uma notificação de sucesso por SNS/SMS.

O mesmo `image_tag` é usado nos dois ambientes.

**Validação do deploy:** o script aguarda o estado do container e testa `http://localhost/status`. O Dockerfile define um `HEALTHCHECK`. A validação é local à EC2; ela não substitui uma verificação HTTPS externa.

## 5. Rollback

O projeto oferece **rollback manual acionado pelo GitHub Actions**, reutilizando o workflow de CD e uma imagem anterior ainda disponível no ECR.

### Procedimento

1. Abra o repositório no GitHub e acesse **Actions → CD**.
2. Selecione **Run workflow**.
3. Preencha `image_tag` com o **SHA/tag de uma imagem anterior** armazenada no ECR.
4. Inicie o workflow e acompanhe os logs.
5. Confirme o resultado do deploy em **staging** e, em seguida, **production**.
6. Valide `/status` nos dois ambientes e confira os logs do SSM/CloudWatch.

O CD utiliza a mesma rotina de deploy para uma versão nova ou anterior. Assim, **não é necessário reconstruir a imagem** para restaurar uma versão publicada.

Para confirmar a versão restaurada, consulte a imagem do container via SSM (`docker inspect lacrei-api`) e compare com a tag solicitada, além de validar `/status`.

## 6. Observabilidade e logs

### Logs de deploy

O CD habilita saída do SSM para o grupo **`/lacrei/deploy`** no CloudWatch Logs, com retenção de **14 dias**. O GitHub Actions também exibe o andamento e o resultado das invocações.

### Logs da aplicação

A aplicação escreve em stdout/stderr do container. Para consultar, execute remotamente via SSM:

```bash
docker logs --tail 200 lacrei-api
```

**Importante:** os logs da aplicação **não são enviados automaticamente ao CloudWatch** nesta implementação. Eles são consultados no Docker da instância.

### Métricas e alarmes

O dashboard **`lacrei-api`** inclui CPU e status checks das instâncias de staging e produção.

O Terraform configura, para cada ambiente:

- alarme de CPU média **≥ 80%** por dois períodos de **5 minutos**;
- alarme de falha de status da EC2 em dois períodos de **1 minuto**.

Os alarmes existem no CloudWatch, mas o código fornecido **não associa ações SNS a eles**. A notificação SNS atual é um **SMS opcional de sucesso do deploy**, não um alerta automático desses alarmes.

## 7. Segurança e limitações

### Checklist de segurança

| Controle | Situação | Observação |
| --- | --- | --- |
| Credenciais AWS fora do repositório | ✅ | GitHub Secrets |
| Permissões IAM separadas para CI/CD e EC2 | ✅ | Usuário para pipeline; role para EC2 |
| Publicação ECR restrita ao repositório da aplicação | ✅ | Política IAM específica |
| ECR com tags imutáveis | ✅ | Evita sobrescrita de tags |
| Verificação de imagens no push | ✅ | `scan_on_push = true` |
| Deploy remoto sem abrir SSH | ✅ | AWS Systems Manager |
| Descoberta de EC2 por tags | ✅ | Não depende de IDs fixos |
| Teste do container antes de publicar | ✅ | CI e Docker HEALTHCHECK |
| Logs de deploy acessíveis | ✅ | GitHub Actions e CloudWatch |
| Rollback em produção | ✅ | image_tag do ECR e run workflow do Github Actions |
| HTTPS/TLS público | ❌ | **Não implementado** |

## 8. Problemas técnicos, decisões e aprendizados

Esta seção documenta decisões verificáveis na implementação e pontos de atenção identificados durante o desenvolvimento. **Os itens abaixo não devem ser interpretados como um histórico exaustivo de incidentes**, pois nem todos os erros e suas soluções estão registrados no repositório.

| Situação / desafio | Decisão adotada | Motivo |
| --- | --- | --- |
| Instâncias EC2 podem ser recriadas pelo Terraform | Descoberta por tags `Name=staging` e `Name=production` | Evitar IDs fixos no pipeline |
| Executar deploy remoto sem abrir SSH | SSM Run Command | Reduzir superfície de acesso administrativo |
| Autenticar o pipeline na AWS | Usuário IAM + GitHub Secrets | Integrar com Actions sem credenciais no código |
| Autenticar as EC2 no ECR | IAM Role + instance profile | Evitar access keys persistentes nas máquinas |
| Distinguir versões e possibilitar restauração | Tag de imagem com SHA e imutabilidade no ECR | Rastreabilidade e rollback por versão |
| Garantir a ordem dos ambientes | Staging antes de production, com checagem do SSM | Interromper promoção quando staging falhar |
| Preparar instâncias recém-criadas | `user_data.sh` e verificação de dependências no deploy | Reproduzir o ambiente de execução |
| Diagnosticar falhas de container | `docker inspect`, `docker logs`, health check e `/status` | Melhorar visibilidade das falhas |
| Tornar o deploy auditável | Saída do SSM no CloudWatch Logs | Facilitar diagnóstico posterior |
| HTTPS sem domínio/certificado configurado | Documentar a limitação e propor ALB + ACM | Falta de domínio próprio 😢 |

## 9. Registro de erros encontrados

Durante o desenvolvimento, alguns problemas apareceram no fluxo real de deploy e direcionaram ajustes na implementação:

| Erro observado | Causa identificada | Correção aplicada |
| --- | --- | --- |
| O CD não era disparado após o CI | O workflow de CD estava escutando um nome de workflow diferente do CI real | Ajuste do `workflow_run.workflows` para `CI` e inclusão de `workflow_dispatch` para execução manual |
| `No SSM managed instance found for tag Name=staging` | A busca inicial dependia de instâncias já registradas no SSM; instâncias recém-criadas podiam ainda não estar online no SSM | O CD passou a localizar EC2 por tag via `ec2:DescribeInstances`, esperar `PingStatus=Online` no SSM e só então enviar o comando |
| `/tmp/deploy.sh: line 12: aws: command not found` | A instância não tinha AWS CLI instalada para executar o login no ECR | `user_data.sh` e `deploy.sh` passaram a instalar/verificar dependências antes do deploy |
| `Package 'awscli' has no installation candidate` | O pacote `awscli` não estava disponível no repositório APT usado pela imagem Ubuntu Noble | Substituição da instalação via `apt` pelo instalador oficial do AWS CLI v2 usando `curl` e `unzip` |
| `/tmp/deploy.sh: line 13: docker: command not found` | Instância criada sem Docker disponível no momento do deploy | Instalação de `docker.io` no `user_data.sh` e verificação de dependência também dentro do `deploy.sh` |
| `curl: (56) Recv failure: Connection reset by peer` na validação local | A validação HTTP podia ocorrer antes de o container estar saudável ou sem informações suficientes para diagnosticar a falha | O deploy passou a aguardar o estado do container, usar retries no `curl` e imprimir `docker ps`, `docker inspect` e `docker logs` em caso de erro |
| Notificação de deploy concluído | Não havia aviso fora do GitHub Actions quando staging e production terminavam com sucesso | Inclusão opcional de SMS via SNS usando o secret `SNS_PHONE_NUMBER` |

Também foi considerada uma migração para ECS Fargate para reduzir a dependência de preparação manual das EC2, mas a abordagem foi descartada para manter o escopo mais simples e compatível com a infraestrutura já construída.
