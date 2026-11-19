# Wildmon 3D — Beta 0.1

Wildmon 3D é um protótipo original de aventura e captura de criaturas em terceira pessoa, desenvolvido no Godot 4.4.1. Esta versão inicial serve para validar a cena 3D, os controles por toque, a câmera e o primeiro fluxo de captura em dispositivos Android.

> **Estado do projeto:** protótipo experimental. A existência do workflow não significa que já exista um APK pronto; a compilação precisa terminar com sucesso no GitHub Actions e publicar o artefato.

## O que existe nesta beta

- Pequeno cenário 3D low-poly com terreno, caminho e árvores.
- Personagem controlável por botões direcionais na tela.
- Câmera de acompanhamento em terceira pessoa.
- Criatura original chamada **Brasafofo**.
- Captura por aproximação e botão de ação.
- Interface e mensagens em português.
- Renderizador Compatibility (OpenGL), selecionado para a compatibilidade móvel.

## Como jogar

1. Abra o jogo no Android.
2. Use os botões direcionais na parte inferior da tela para caminhar.
3. Aproxime-se do Brasafofo.
4. Quando estiver perto, toque em **CAPTURAR**.

Os controles e o conteúdo são provisórios e podem mudar nas próximas versões.

## Gerar o APK pelo GitHub Actions

O workflow está em `.github/workflows/android-apk.yml` e exporta o preset **Android** definido em `export_presets.cfg`.

### Quando a compilação é iniciada

- Automaticamente a cada push na branch `main`.
- Manualmente pela aba **Actions**, selecionando **Build Wildmon 3D Android APK** e tocando em **Run workflow**.

### Etapas executadas

1. Baixa o código do repositório.
2. Prepara Java 17 e o Android SDK.
3. Instala os componentes Android definidos no workflow.
4. Cria uma chave Android de depuração temporária no runner.
5. Executa a exportação com Godot 4.4.1 usando `firebelley/godot-export@v8.0.0`.
6. Confere se o arquivo APK esperado existe e não está vazio.
7. Publica o arquivo como artefato `Wildmon3D-Beta01-APK`.

A ação de exportação utiliza o executável Linux Headless e os templates da mesma versão do Godot. Consulte a documentação oficial da ação para detalhes dos parâmetros: https://github.com/firebelley/godot-export

### Baixar e instalar

1. Abra a aba **Actions** deste repositório.
2. Entre na execução mais recente do workflow.
3. Confirme que o status terminou em verde (**Success**).
4. Na seção **Artifacts**, baixe `Wildmon3D-Beta01-APK`.
5. Extraia o ZIP e instale o APK no Android.

Se a execução estiver vermelha (**Failed**), não há APK validado nessa execução. Abra o job **Export Wildmon 3D Beta 0.1**, expanda a etapa que falhou e consulte a mensagem do log. O artefato tem retenção configurada para 14 dias; depois desse prazo, uma nova compilação será necessária.

## Sobre o APK

- Formato: APK Android.
- Arquitetura configurada: `arm64-v8a`.
- Identificador do pacote: `com.wildmon.game`.
- Versão inicial: `0.1`.
- Assinatura: chave de depuração temporária criada durante a compilação.
- Uso: testes da beta, não publicação final.

O Android pode pedir autorização para instalar aplicativos obtidos fora da loja. Como esta é uma compilação de depuração, não a utilize como versão final de distribuição. Uma futura versão de lançamento deverá usar uma chave de assinatura própria, armazenada com segurança nos secrets do GitHub.

## Estrutura do repositório

| Caminho | Finalidade |
| --- | --- |
| `project.godot` | Configurações gerais e cena inicial do projeto. |
| `scenes/main.tscn` | Cena principal do jogo. |
| `scripts/game.gd` | Criação do cenário, personagem, criatura, controles e captura. |
| `export_presets.cfg` | Preset de exportação Android e caminho de saída do APK. |
| `.github/workflows/android-apk.yml` | Automação de compilação e publicação do artefato APK. |

## Tecnologias

- Godot Engine 4.4.1
- GDScript
- Android SDK
- GitHub Actions
- Renderizador Compatibility (OpenGL)

## Próximas etapas sugeridas

- Validar a compilação Android em CI e instalar o APK em um aparelho real.
- Melhorar a movimentação, a câmera e o layout dos controles.
- Criar mais criaturas e uma interface de equipe/inventário.
- Adicionar salvamento de progresso e uma área maior de exploração.

Todos os nomes, criaturas e elementos deste protótipo são originais.
