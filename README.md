# Wildmon 3D — Beta 1.0

Wildmon 3D é um jogo original de exploração e captura de criaturas em terceira pessoa, desenvolvido no Godot 4.4.1 com foco em Android.

## Direção da Beta 1.0

Esta atualização reúne uma reformulação visual ampla do protótipo:

- Terreno ondulado com material procedural, variação de cor e detalhe em diferentes escalas.
- Trilha sinuosa integrada ao relevo.
- Colinas distantes, neblina atmosférica e iluminação de fim de tarde.
- Clareira com lago, margem de terra e pedras.
- Mais árvores, copas em camadas, galhos, plantas, pedras e vegetação rasteira.
- Personagem explorador com roupas, mochila, detalhes e movimento sutil ao caminhar.
- Brasafofo redesenhado com focinho, barriga clara, orelhas internas, olhos e cauda flamejante.
- Criatura com movimento de espera e deslocamento suave pelo ambiente.
- Interface mobile redesenhada com painel translúcido e botões estilizados.

## Controles

- Use os botões direcionais para caminhar.
- Arraste o lado direito da tela para girar a câmera.
- Aproxime-se do Brasafofo e toque em **CAPTURAR**.

## Tecnologia e compatibilidade

- Godot Engine 4.4.1
- GDScript
- Renderizador Compatibility (OpenGL)
- Exportação Android ARM64
- GitHub Actions para validação e compilação do APK

O projeto prioriza desempenho em aparelhos Android intermediários. Os modelos e ambientes desta fase são construídos proceduralmente; a próxima evolução visual poderá incorporar modelos 3D externos otimizados e animações completas.

## Estrutura

| Caminho | Finalidade |
| --- | --- |
| `project.godot` | Configurações gerais do jogo. |
| `scenes/main.tscn` | Cena principal. |
| `scripts/game.gd` | Ambiente, personagem, criatura, controles e captura. |
| `export_presets.cfg` | Configuração de exportação Android. |
| `.github/workflows/android-apk.yml` | Validação e compilação automática do APK. |

Todos os nomes, criaturas e elementos deste protótipo são originais.
