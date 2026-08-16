# Guia do primeiro commit e configuração do GitHub

Este guia parte de Linux Mint e de um pacote recém-extraído chamado `mnemos-platform`. A estratégia recomendada usa SSH para autenticação e mantém `main` como branch estável.

## 1. Instalar e conferir as ferramentas

```bash
sudo apt update
sudo apt install -y git openssh-client

git --version
ssh -V
```

O GitHub exige autenticação para enviar código. Este guia usa uma chave SSH Ed25519.

## 2. Entrar na pasta correta

Depois de extrair o ZIP:

```bash
cd ~/caminho/onde/voce/extraiu/mnemos-platform
pwd
ls
```

Confirme que a saída contém `README.md`, `app/`, `backend/`, `firmware/`, `spec/` e `SETUP_GITHUB.md`.

## 3. Configurar a identidade dos commits

O nome registrado pelo Git é a identidade exibida nos commits e não precisa ser idêntico ao nome de usuário do GitHub.

Para configurar globalmente:

```bash
git config --global user.name "SEU NOME"
git config --global user.email "SEU_EMAIL_ASSOCIADO_AO_GITHUB"
git config --global init.defaultBranch main
git config --global core.autocrlf input
```

Confira:

```bash
git config --global --get user.name
git config --global --get user.email
git config --global --get init.defaultBranch
```

Se você preferir que essa identidade valha somente para Mnemos, omita `--global` nos dois primeiros comandos depois de executar `git init`.

O GitHub também oferece um endereço `noreply` caso você queira manter o e-mail pessoal privado. Use como `user.email` um endereço que esteja associado à sua conta do GitHub para que os commits sejam vinculados corretamente ao perfil.

## 4. Configurar SSH para GitHub

Primeiro veja se já existe uma chave que você deseja reutilizar:

```bash
ls -al ~/.ssh
```

Se não houver uma chave apropriada, gere uma nova:

```bash
ssh-keygen -t ed25519 -C "SEU_EMAIL_ASSOCIADO_AO_GITHUB"
```

Aceite o caminho padrão `~/.ssh/id_ed25519` se ele estiver livre e use uma passphrase. Inicie o agente e carregue a chave:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Mostre a chave pública:

```bash
cat ~/.ssh/id_ed25519.pub
```

Copie somente a linha pública. No GitHub abra **Settings → SSH and GPG keys → New SSH key**, escolha o tipo **Authentication Key**, dê um nome ao computador e cole a chave pública.

Teste a conexão:

```bash
ssh -T git@github.com
```

Na primeira conexão, confirme a fingerprint somente se ela corresponder à fingerprint publicada pelo GitHub. Uma autenticação bem-sucedida informa que o GitHub reconheceu sua conta, embora não ofereça shell interativo.

Documentação oficial consultada: `https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent` e `https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account`.

## 5. Verificar o pacote antes do Git

O repositório foi preparado para não carregar builds e caches, mas faça a verificação local:

```bash
bash tools/repository/check-before-commit.sh
```

Depois procure arquivos sensíveis manualmente:

```bash
find . -maxdepth 4 \
  \( -name '.env' -o -name '*.pem' -o -name '*.key' -o -name '*.jks' -o -name '*.keystore' \) \
  -print
```

O resultado deve estar vazio, exceto por arquivos de exemplo explicitamente seguros, como `backend/.env.example`.

## 6. Inicializar o repositório local

```bash
git init
git branch -M main
```

Confirme:

```bash
git status
git branch --show-current
```

O segundo comando deve retornar `main`.

## 7. Examinar exatamente o que entrará no primeiro commit

Adicione os arquivos ao staging:

```bash
git add .
```

Agora não faça o commit ainda. Examine:

```bash
git status
```

Para listar todos os caminhos staged:

```bash
git diff --cached --name-status
```

Para procurar alterações com whitespace problemático:

```bash
git diff --cached --check
```

Se aparecer uma credencial ou arquivo que não deveria ser versionado, remova-o do staging com:

```bash
git restore --staged CAMINHO_DO_ARQUIVO
```

Corrija `.gitignore` se necessário antes de prosseguir.

## 8. Criar o primeiro commit

Quando o staging estiver correto:

```bash
git commit -m "feat: establish Mnemos v0.4 platform architecture"
```

Confira:

```bash
git log --oneline --decorate -n 5
```

## 9. Criar o repositório no GitHub

No GitHub, crie um repositório chamado `mnemos-platform`. Para este primeiro push, crie o repositório **vazio**: não marque a criação automática de README, `.gitignore` ou licença. Isso evita criar um commit remoto concorrente antes do primeiro push local.

Escolha `Private` enquanto ainda estiver decidindo licenciamento, segredos, documentação pública e estratégia de publicação. A visibilidade pode ser alterada depois.

A orientação oficial do GitHub para adicionar código local também recomenda que o novo repositório remoto seja criado sem README, licença ou gitignore quando o projeto local já contém esses arquivos: `https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github`.

## 10. Associar o remoto

No Quick Setup do repositório, copie a URL SSH. Ela terá o formato:

```text
git@github.com:SEU_USUARIO/mnemos-platform.git
```

Configure:

```bash
git remote add origin git@github.com:SEU_USUARIO/mnemos-platform.git
```

Confira antes de enviar qualquer dado:

```bash
git remote -v
```

## 11. Primeiro push

```bash
git push -u origin main
```

O parâmetro `-u` registra `origin/main` como upstream. A partir daí, em commits normais, `git push` e `git pull` já sabem qual branch remota utilizar.

## 12. Criar a tag inicial v0.4.0

Depois de confirmar que o primeiro commit está corretamente publicado:

```bash
git tag -a v0.4.0 -m "Mnemos v0.4.0 - minimal HMI, desired-state sync and resilient connectivity"
git push origin v0.4.0
```

A tag representa o estado do código-fonte. ZIPs, APKs, `.bin` e outros artefatos compilados não devem ser adicionados ao Git apenas para representar releases; eles podem ser anexados posteriormente a uma GitHub Release associada à tag.

## 13. Configurar a branch main no GitHub

Quando o repositório já estiver no GitHub, abra **Settings → Branches** ou **Settings → Rules → Rulesets**, conforme a interface disponível para sua conta. Para `main`, recomenda-se impedir force push e exclusão. Quando os workflows estiverem estáveis, habilite também a exigência de status checks antes do merge. Se outras pessoas passarem a contribuir, exija Pull Request para mudanças em `main`.

O GitHub documenta branch protection e rulesets como mecanismos para impor reviews e status checks: `https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule`.

Não habilite imediatamente uma regra que exija checks que ainda não existem ou que ainda estejam falhando; isso pode bloquear seu próprio fluxo antes de a CI estar validada.

## 14. Fluxo diário sugerido

Para uma nova funcionalidade:

```bash
git switch main
git pull --ff-only
git switch -c feature/NOME-DA-FUNCIONALIDADE
```

Depois de trabalhar:

```bash
git status
git diff
bash tools/repository/check-before-commit.sh

git add CAMINHOS_QUE_REALMENTE_DEVEM_ENTRAR
git diff --cached --check
git diff --cached

git commit -m "feat(escopo): descreve a alteração"
git push -u origin feature/NOME-DA-FUNCIONALIDADE
```

Abra um Pull Request para `main`. Após o merge, remova a branch temporária.

## 15. Padrão de commits

O repositório adota prefixos semânticos. Use `feat` para funcionalidade, `fix` para correção, `docs` para documentação, `test` para testes, `refactor` para reorganização sem mudança de comportamento, `build` para toolchain/build e `chore` para manutenção.

Exemplos:

```text
feat(firmware): add persistent Wi-Fi provisioning
fix(mobile): preserve terminal state after failed sync
docs(spec): clarify mnemos.card/v1 extensions
test(schema): validate canonical networking fixture
build(android): update compatible Gradle toolchain
```

## 16. Licença antes de tornar público

Este pacote não escolhe uma licença por você. Sem uma licença explícita, terceiros não recebem automaticamente permissão para copiar, modificar e redistribuir o código apenas porque o repositório é visível. Leia `docs/governance/licensing.md`, defina a política e só então adicione `LICENSE`.

## 17. Checklist final do primeiro push

Antes de executar `git push -u origin main`, confirme que `git status` não mostra caches ou binários, `git diff --cached --check` não reporta problemas, nenhum `.env` real está staged, nenhum token ou senha aparece em `git diff --cached`, `origin` aponta para o repositório correto e a branch local é `main`.
