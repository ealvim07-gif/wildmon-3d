# Wildmon 3D — desenvolvimento da Beta 2.0

Wildmon 3D é um jogo original de exploração e captura de criaturas em terceira pessoa, desenvolvido no Godot 4.4.1 com foco em Android.

## Base atual e direção da Beta 2.0

Esta atualização reúne uma reformulação visual ampla do protótipo:

- Terreno gerado pelo Terrain3D 1.0.2, com malha LOD, colisão e camadas de grama/solo texturizadas.
- Trilha sinuosa integrada ao relevo.
- Relevo com cristas alongadas, silhuetas facetadas ao horizonte, neblina atmosférica e iluminação de fim de tarde.
- Clareira com lago, margem de terra e pedras.
- Primeira integração dos modelos 3D texturizados Quaternius Stylized Nature MegaKit (Standard, CC0), com árvores, pinheiros, arbustos, samambaias, pedras e vegetação.
- Personagem explorador com roupas, mochila, detalhes e movimento sutil ao caminhar.
- Brasafofo redesenhado com focinho, barriga clara, orelhas internas, olhos e cauda flamejante.
- Segunda espécie original, Pedralume: criatura rochosa de quatro patas, corpo facetado e cristais dorsais; alterna com o Brasafofo durante os encontros.
- Coleção separada por espécie, com contadores persistentes para Brasafofo e Pedralume.
- Criatura com movimento de espera e deslocamento suave pelo ambiente.
- Interface mobile com analógico virtual grande, zona morta configurada, câmera por arraste independente e botão de captura ampliado.
- Vegetação baixa com animação procedural leve de brisa, mantendo árvores e elementos maiores estáveis para economizar processamento.

## Controles

- Use o analógico virtual no canto inferior esquerdo para caminhar em qualquer direção; a intensidade do movimento acompanha o deslocamento do controle.
- Arraste a área livre do lado direito, acima dos botões, para girar a câmera e ajustar a inclinação.
- Aproxime-se da criatura e toque em **CAPTURAR**. A coleção de Brasafofo e Pedralume é salva localmente.

## Tecnologia e compatibilidade

- Godot Engine 4.4.1
- GDScript
- Renderizador Compatibility (OpenGL)
- Exportação Android ARM64
- GitHub Actions para validação e compilação do APK

O projeto prioriza desempenho em aparelhos Android intermediários. Os modelos de natureza são obtidos automaticamente pelo script `scripts/fetch_world_assets.sh` a partir do espelho público do pacote Quaternius. Os arquivos são licenciados em CC0 1.0 e são baixados durante a validação; não é necessário armazenar os modelos e texturas no repositório. O pacote Terrain3D 1.0.2 inclui binários Android ARM64 e Linux. A validação automatizada importa o projeto e inicia o mundo em modo headless no Linux; isso confirma a integridade básica do projeto, mas não substitui o teste visual e de desempenho em um aparelho Android real.

## Estrutura

| Caminho | Finalidade |
| --- | --- |
| `project.godot` | Configurações gerais do jogo. |
| `scenes/main.tscn` | Cena principal. |
| `scripts/game.gd` | Ambiente, modelos de natureza, personagem, criatura, controles e captura. |
| `scripts/fetch_world_assets.sh` | Baixa os modelos e texturas CC0 usados no cenário. |
| `scripts/fetch_terrain3d.sh` | Baixa Terrain3D 1.0.2 e valida os binários Android ARM64. |
| `.github/workflows/validate-world.yml` | Importa e inicia o mundo no Godot headless sem gerar APK. |
| `export_presets.cfg` | Configuração de exportação Android. |
| `.github/workflows/android-apk.yml` | Validação e compilação automática do APK. |

Todos os nomes, criaturas e elementos deste protótipo são originais.
