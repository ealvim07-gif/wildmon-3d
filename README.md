# Wildmon 3D — Beta 0.1

Wildmon 3D é um protótipo original de aventura e captura de criaturas em 3D, desenvolvido com Godot Engine 4.4.1. O projeto está em fase inicial e prioriza testes de movimentação, câmera, exploração e captura em celulares Android.

## Conteúdo da Beta 0.1

- Ambiente 3D low-poly com terreno, caminho e árvores.
- Personagem controlável por botões na tela.
- Câmera de acompanhamento em terceira pessoa.
- Primeira criatura original: **Brasafofo**.
- Captura por proximidade.
- Interface e mensagens em português.
- Renderizador Compatibility (OpenGL), escolhido para ampliar a compatibilidade com dispositivos móveis.

## Controles

Use os botões direcionais na tela para movimentar o personagem. Aproxime-se do Brasafofo e toque no botão de captura quando ele estiver ao alcance.

## Gerar o APK automaticamente

O repositório possui um workflow do GitHub Actions em `.github/workflows/android-apk.yml`.

A compilação é iniciada automaticamente quando há um push na branch `main`. Também pode ser iniciada manualmente:

1. Abra a aba **Actions** do repositório.
2. Escolha **Build Wildmon 3D Android APK**.
3. Toque em **Run workflow** e confirme.
4. Aguarde a execução terminar com status verde.
5. Abra a execução concluída e localize **Artifacts**.
6. Baixe **Wildmon3D-Beta01-APK** e extraia o APK do arquivo ZIP.

O workflow prepara Java 17, Android SDK e uma chave de depuração temporária, executa a exportação com `firebelley/godot-export@v8.0.0` e verifica se o APK foi realmente criado antes de publicar o artefato. A chave é gerada durante a compilação e não é armazenada no repositório.

## Instalação e segurança

Esta é uma compilação **debug** destinada a testes. O Android pode solicitar autorização para instalar aplicativos desta origem. O APK de depuração não deve ser tratado como versão final de publicação. Uma versão de lançamento deverá usar uma chave própria, guardada em segredo e fora do repositório.

## Estrutura principal

- `project.godot` — configurações do projeto e cena inicial.
- `scenes/main.tscn` — cena principal.
- `scripts/game.gd` — lógica do protótipo.
- `export_presets.cfg` — preset de exportação Android.
- `.github/workflows/android-apk.yml` — compilação automática do APK.

## Tecnologia

- Godot Engine 4.4.1
- GDScript
- Android arm64-v8a
- Renderizador Compatibility (OpenGL)

Todos os nomes, criaturas e elementos do protótipo são originais.
