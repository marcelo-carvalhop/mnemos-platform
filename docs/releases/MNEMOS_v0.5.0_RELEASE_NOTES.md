# Mnemos v0.5.0-preview.3 — notas de release

Esta preview é focada em firmware CYD. Não substitui o trabalho em andamento do app/web. Mudanças principais: BLE removido; DirectSync via SoftAP/HTTP; HMI reduzida; cartões v2 com múltipla escolha e verdadeiro/falso; correção automática de tipos objetivos; confiança separada de acerto e esforço; PracticeSession sem alteração do scheduler; LearningModel D/S/R isolado; histórico e outbox separados; métricas metodológicas exportadas por JSON; Device Protocol v4.

Ainda não é uma release final porque o primeiro `pio run` deve ser executado na toolchain local do projeto. Qualquer correção de compatibilidade encontrada deve entrar nesta mesma linha preview antes da tag v0.5.0.


## Preview.2 — agenda visível e OTA A/B

A preview.3 torna o scheduler observável apenas no nível útil ao estudante. Home, conclusão de sessão e Menu > Agenda consomem um único `ScheduleService`, enquanto o reagendamento individual de cada card permanece transparente. Também preserva a correção da semântica de primeiro erro/reaprendizado e a classificação de maturidade de cards já tentados.

Com base no build físico da preview.1 (1.151.657 bytes), o CYD deixa `huge_app.csv` e adota `mnemos_ota.csv` com dois slots de 1,5 MiB e LittleFS de 960 KiB.
