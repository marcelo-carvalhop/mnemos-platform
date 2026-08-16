# Mnemos HMI Principles — v0.4

## Product rule

**Simplicity is a functional requirement.** The dedicated terminal exists to remove distraction, and every Mnemos interface must preserve that identity. A screen has one primary responsibility and must not borrow unrelated metrics, reminders, promotions or secondary actions merely because data is available.

The mobile application prepares and manages study. The terminal is the only official study surface: it presents prompts, reveals answers and records ratings/confidence. Mobile and web may create, edit, import and organize cards, but they do not offer a parallel study session.

## Mobile home

Home is navigation only. It contains the Mnemos identity and four destinations: **Biblioteca**, **Dispositivo**, **Sincronização** and **Estatísticas**, plus access to Settings. It contains no streak, due count, retention percentage, reminders, learning forecast, recommendation feed, advertising surface or study CTA.

## Biblioteca

Biblioteca answers only: “what content do I own and how do I edit it?” Deck rows show identity and card count. Maturity, retention and historical performance are excluded. Creating, renaming, archiving and deleting content are valid library operations.

## Dispositivo

Dispositivo answers only: “which Mnemos is this and how is it configured?” It shows device identity, model, firmware, protocol/capacity and the entry point to connection configuration. It does not decide which decks are installed.

## Conexão

Conexão manages transport configuration only. Pairing identifies the terminal and stores a network profile/backend device credential. Pairing never installs a deck. Known network profiles remain on the terminal until forgotten and survive Wi-Fi radio power-off.

## Sincronização

Sincronização expresses desired state, not file transfer. For each deck the user chooses only one semantic state: **No Mnemos** or **Somente no app**. The UI does not ask “upload or download?”. Content authority is App/Backend → Terminal. Study-event authority is Terminal → App/Backend.

The app computes ADD/UPDATE/REMOVE operations by comparing desired state with actual device state. Reviews are always imported automatically and never require a checkbox. When offline, a change of desired state remains pending instead of becoming an error.

## Estatísticas

All learning metrics live here: retention, maturity, forecast, review history and other evidence derived from study. Metrics do not leak back into Home, Biblioteca or Conexão.

## Terminal

The terminal home remains deliberately small. It presents only the information necessary to start studying, resume an interrupted session when one exists, and access **Sincronização** or **Conexão**. The terminal connection screen controls network configuration and Wi-Fi power. The terminal synchronization screen offers backend sync and explicit Bluetooth sync. BLE advertising is not permanent.

## Visual identity

Use the Mnemos palette consistently: Marfim Calmo `#F4F1E8`, Grafite Profundo `#1F1F1F`, Sálvia Analógica `#7A8B72`, Azul Petróleo `#365462`, Terracota Contida `#B56E52`, Cinza Névoa `#D9D5CC` and Latão Fosco `#B8A27A`. Motion is functional and scarce. Interfaces must remain understandable without animation because the final terminal uses e-paper.

## Feedback

Operations report concrete stages and outcomes instead of generic spinners. User-facing errors explain a recoverable action; technical reason codes belong in expandable diagnostics. A successful synchronization should communicate what changed, but should not turn into a gamification surface.
