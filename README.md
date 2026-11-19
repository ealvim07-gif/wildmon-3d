# Wildmon 3D — Beta 0.1

Wildmon 3D é um protótipo original de aventura e captura de criaturas em terceira pessoa, desenvolvido no Godot 4.4.1. A versão atual serve para validar a cena 3D, os controles por toque, a câmera e o primeiro fluxo de captura.

> **Estado atual:** em correção e validação. A automação está temporariamente limitada a verificações do projeto. **Nenhum APK é exportado nesta fase.** A exportação Android só deverá ser reativada depois que as verificações do projeto passarem e a configuração Android for revisada separadamente.

## O que existe nesta beta

- Pequeno cenário 3D low-poly com terreno, caminho e árvores.
- Personagem controlável por botões direcionais na tela.
- Câmera de acompanhamento em terceira pessoa.
- Criatura original chamada **Brasafofo**.
- Captura por aproximação e botão de ação.
- Interface e mensagens em português.
- Renderizador Compatibility (OpenGL), selecionado para compatibilidade móvel.

## Como jogar

1. Use os botões direcionais na parte inferior da tela para caminhar.
2. Aproxime-se do Brasafofo.
3. Quando estiver perto, toque em **CAPTURAR**.

Os controles e o conteúdo são provisórios e podem mudar nas próximas versões.

## Validação automática (sem exportação)

O workflow está em `.github/workflows/android-apk.yml`. Ele executa apenas verificações com Godot 4.4.1:

1. Baixa e verifica a versão do executável Godot.
2. Analisa a sintaxe do GDScript.
3. Importa o projeto e valida recursos/cenas.
4. Inicia a cena principal em modo headless por um teste curto.
5. Confirma que o workflow não contém etapas de exportação nem de publicação de APK.

O workflow **não instala Android SDK, não configura assinatura, não executa `--export-debug` ou `--export-release` e não publica artefatos APK**.

Acompanhe as verificações na aba [Actions](https://github.com/ealvim07-gif/wildmon-3d/actions). Se alguma etapa falhar, o log deverá apontar o erro a corrigir antes de avançar.

## Sobre a futura versão Android

A exportação Android permanece suspensa. Antes de reativá-la, ainda será necessário revisar separadamente o preset Android, os caminhos do Java 17 e Android SDK, as versões de SDK/build-tools, a assinatura e a compatibilidade em aparelho real.

Quando todas as verificações estiverem aprovadas, a exportação será reintroduzida em uma etapa separada e explicitamente autorizada.

## Estrutura do repositório

| Caminho | Finalidade |
| --- | --- |
| `project.godot` | Configurações gerais e cena inicial do projeto. |
| `scenes/main.tscn` | Cena principal do jogo. |
| `scripts/game.gd` | Criação do cenário, personagem, criatura, controles e captura. |
| `export_presets.cfg` | Preset Android reservado para a futura fase de exportação. |
| `.github/workflows/android-apk.yml` | Validação automática sem exportação. |

## Tecnologias

- Godot Engine 4.4.1
- GDScript
- GitHub Actions
- Renderizador Compatibility (OpenGL)

Todos os nomes, criaturas e elementos deste protótipo são originais.
