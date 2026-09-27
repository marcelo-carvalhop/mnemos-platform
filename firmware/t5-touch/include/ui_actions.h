#pragma once

#include <Arduino.h>

enum class UiAction : uint8_t {
    None = 0,
    PrimaryStudy,
    OpenMenu,
    OpenSync,
    OpenAgenda,
    OpenConnection,
    SyncBackend,
    SyncPhone,
    ConfigureNetwork,
    ToggleWifi,
    Back,
    CancelLocalLink,
    AnswerReady,

    // Mantidos para preservar valores da preview anterior.
    AbortStudy,
    ToggleOrientation,

    Choice0,
    Choice1,
    Choice2,
    Choice3,
    ConfidenceLow,
    ConfidenceMedium,
    ConfidenceHigh,
    SelfIncorrect,
    SelfCorrect,
    EffortDifficult,
    EffortNormal,
    EffortEasy,
    Continue,
    StudyAgain,
    Home,

    // Extensão touch-first conforme HMI_T5_TOUCH_GUIDELINES_v0.1.
    OpenDecks,
    ToggleDeckFilter,
    ClearDeckFilter,
    AbortSession,
    ConfirmAbort,
    CancelAbort,
    RotateOrientation,

    // Wi-Fi touch-first.
    ScanWifi,
    SelectWifiNetwork,
    WifiKey,
    WifiShift,
    WifiSymbols,
    WifiBackspace,
    WifiSpace,
    WifiConnect,
    WifiCancel,

    // microSD.
    OpenStorage,
    RefreshSd,
    ImportSdFile,
    ExportLibraryToSd,
};

inline const char* uiActionName(UiAction action) {
    switch (action) {
        case UiAction::PrimaryStudy:
            return "Iniciar/retomar estudo";
        case UiAction::OpenMenu:
            return "Abrir menu";
        case UiAction::OpenDecks:
            return "Abrir decks";
        case UiAction::OpenSync:
            return "Sincronizacao";
        case UiAction::OpenAgenda:
            return "Agenda";
        case UiAction::OpenConnection:
            return "Conexao";
        case UiAction::SyncBackend:
            return "Sincronizar conta";
        case UiAction::SyncPhone:
            return "Sincronizar celular";
        case UiAction::ConfigureNetwork:
            return "Configurar rede";
        case UiAction::ToggleWifi:
            return "Alternar Wi-Fi";
        case UiAction::Back:
            return "Voltar";
        case UiAction::CancelLocalLink:
            return "Cancelar conexao local";
        case UiAction::AnswerReady:
            return "Ver resposta";
        case UiAction::AbortStudy:
            return "Abortar estudo legado";
        case UiAction::ToggleOrientation:
            return "Alternar orientacao legado";
        case UiAction::Choice0:
            return "Alternativa 1";
        case UiAction::Choice1:
            return "Alternativa 2";
        case UiAction::Choice2:
            return "Alternativa 3";
        case UiAction::Choice3:
            return "Alternativa 4";
        case UiAction::SelfIncorrect:
            return "Nao recuperei";
        case UiAction::SelfCorrect:
            return "Recuperei";
        case UiAction::EffortDifficult:
            return "Dificil";
        case UiAction::EffortNormal:
            return "Normal";
        case UiAction::EffortEasy:
            return "Facil";
        case UiAction::Continue:
            return "Continuar";
        case UiAction::StudyAgain:
            return "Estudar novamente";
        case UiAction::Home:
            return "Home";
        case UiAction::ToggleDeckFilter:
            return "Alternar filtro de deck";
        case UiAction::ClearDeckFilter:
            return "Todos os decks";
        case UiAction::AbortSession:
            return "Solicitar interrupcao";
        case UiAction::ConfirmAbort:
            return "Confirmar interrupcao";
        case UiAction::CancelAbort:
            return "Continuar estudando";
        case UiAction::RotateOrientation:
            return "Girar tela";
        case UiAction::ScanWifi:
            return "Procurar redes Wi-Fi";
        case UiAction::SelectWifiNetwork:
            return "Selecionar rede Wi-Fi";
        case UiAction::WifiKey:
            return "Tecla Wi-Fi";
        case UiAction::WifiShift:
            return "Alternar maiusculas";
        case UiAction::WifiSymbols:
            return "Alternar simbolos";
        case UiAction::WifiBackspace:
            return "Apagar caractere";
        case UiAction::WifiSpace:
            return "Espaco";
        case UiAction::WifiConnect:
            return "Conectar Wi-Fi";
        case UiAction::WifiCancel:
            return "Cancelar Wi-Fi";
        case UiAction::OpenStorage:
            return "Armazenamento";
        case UiAction::RefreshSd:
            return "Atualizar microSD";
        case UiAction::ImportSdFile:
            return "Importar arquivo SD";
        case UiAction::ExportLibraryToSd:
            return "Exportar biblioteca SD";
        case UiAction::None:
        default:
            return "Nenhuma";
    }
}
