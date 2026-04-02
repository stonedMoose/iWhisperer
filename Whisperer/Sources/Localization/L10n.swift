import SwiftUI

// MARK: - Localization Keys

@MainActor
enum L10n {
    // MARK: Settings - Column 1: General
    static var general: String { t("General", "Général", "General", "通用", "Geral", "Allgemein") }
    static var launchAtLogin: String { t("Launch at login", "Lancer au démarrage", "Iniciar sesión automáticamente", "登录时启动", "Iniciar ao entrar", "Bei Anmeldung starten") }
    static var model: String { t("Model", "Modèle", "Modelo", "模型", "Modelo", "Modell") }
    static var speakerIdentification: String { t("Speaker Identification", "Identification du locuteur", "Identificación del hablante", "说话人识别", "Identificação do orador", "Sprecheridentifikation") }
    static var speakerIdentificationCaption: String { t(
        "No account needed. Models downloaded on first use (~95 MB).",
        "Aucun compte requis. Modèles téléchargés au premier lancement (~95 Mo).",
        "No se necesita cuenta. Los modelos se descargan en el primer uso (~95 MB).",
        "无需账户。模型在首次使用时下载（约95 MB）。",
        "Nenhuma conta necessária. Modelos baixados no primeiro uso (~95 MB).",
        "Kein Konto erforderlich. Modelle werden beim ersten Start heruntergeladen (~95 MB)."
    )}
    static var appLanguage: String { t("App Language", "Langue de l'app", "Idioma de la app", "应用语言", "Idioma do app", "App-Sprache") }

    // MARK: Settings - Column 2: Languages
    static var preferredLanguages: String { t("Preferred Languages", "Langues préférées", "Idiomas preferidos", "首选语言", "Idiomas preferidos", "Bevorzugte Sprachen") }
    static var preferredLanguagesCaption: String { t(
        "Shown in the menu bar for quick switching.",
        "Affichées dans la barre de menus pour un changement rapide.",
        "Se muestran en la barra de menús para cambiar rápidamente.",
        "显示在菜单栏中以便快速切换。",
        "Mostrados na barra de menus para troca rápida.",
        "Werden in der Menüleiste zum schnellen Wechseln angezeigt."
    )}

    // MARK: Settings - Column 3: Insert at Caret
    static var insertAtCaret: String { t("Insert at Caret", "Insérer au curseur", "Insertar en el cursor", "在光标处插入", "Inserir no cursor", "An Cursorposition einfügen") }
    static var insertAtCaretCaption: String { t(
        "Hold shortcut to record, release to transcribe and insert text at cursor.",
        "Maintenez le raccourci pour enregistrer, relâchez pour transcrire et insérer le texte au curseur.",
        "Mantén el atajo para grabar, suelta para transcribir e insertar texto en el cursor.",
        "按住快捷键录音，松开后转录并在光标处插入文本。",
        "Segure o atalho para gravar, solte para transcrever e inserir texto no cursor.",
        "Kurzbefehl halten zum Aufnehmen, loslassen zum Transkribieren und Einfügen am Cursor."
    )}
    static var streaming: String { t("Streaming (Beta)", "Streaming (Bêta)", "Streaming (Beta)", "流式传输（测试版）", "Streaming (Beta)", "Streaming (Beta)") }
    static var enableStreamingMode: String { t("Enable streaming mode", "Activer le mode streaming", "Activar modo streaming", "启用流式模式", "Ativar modo streaming", "Streaming-Modus aktivieren") }
    static var streamingCaption: String { t(
        "Type text progressively as you speak instead of waiting until you stop recording. Beta: may not work well in every language.",
        "Saisir le texte progressivement pendant que vous parlez au lieu d'attendre la fin de l'enregistrement. Bêta : peut ne pas fonctionner correctement dans toutes les langues.",
        "Escribir texto progresivamente mientras hablas en vez de esperar a que termine la grabación. Beta: puede no funcionar bien en todos los idiomas.",
        "边说边逐步输入文本，而不是等到录音结束。测试版：可能不适用于所有语言。",
        "Digitar texto progressivamente enquanto fala, em vez de esperar até parar de gravar. Beta: pode não funcionar bem em todos os idiomas.",
        "Text wird beim Sprechen progressiv eingegeben, anstatt bis zum Ende der Aufnahme zu warten. Beta: funktioniert möglicherweise nicht in allen Sprachen."
    )}

    // MARK: Settings - Column 4: Meeting
    static var meeting: String { t("Meeting", "Réunion", "Reunión", "会议", "Reunião", "Besprechung") }
    static var meetingCaption: String { t(
        "Press to start recording, press again to stop and transcribe with speaker labels.",
        "Appuyez pour démarrer l'enregistrement, appuyez à nouveau pour arrêter et transcrire avec identification des locuteurs.",
        "Pulsa para empezar a grabar, pulsa de nuevo para detener y transcribir con etiquetas de hablante.",
        "按下开始录音，再次按下停止并带说话人标签转录。",
        "Pressione para iniciar a gravação, pressione novamente para parar e transcrever com rótulos de orador.",
        "Drücken zum Starten der Aufnahme, erneut drücken zum Stoppen und Transkribieren mit Sprecherkennzeichnung."
    )}
    static var transcriptLocation: String { t("Transcript Location", "Emplacement des transcriptions", "Ubicación de transcripciones", "转录文件位置", "Local das transcrições", "Transkript-Speicherort") }
    static var choose: String { t("Choose...", "Choisir...", "Elegir...", "选择...", "Escolher...", "Auswählen...") }
    static var transcriptLocationCaption: String { t(
        "Meeting transcripts are saved here automatically.",
        "Les transcriptions de réunions sont enregistrées ici automatiquement.",
        "Las transcripciones de reuniones se guardan aquí automáticamente.",
        "会议转录文件将自动保存在此处。",
        "As transcrições de reuniões são salvas aqui automaticamente.",
        "Besprechungstranskripte werden hier automatisch gespeichert."
    )}
    static var aiRefinement: String { t("AI Refinement", "Amélioration IA", "Refinamiento IA", "AI 优化", "Refinamento IA", "KI-Verfeinerung") }
    static var refineTranscriptWithAI: String { t("Refine transcript with AI", "Améliorer la transcription avec l'IA", "Refinar transcripción con IA", "使用AI优化转录", "Refinar transcrição com IA", "Transkript mit KI verfeinern") }
    static var provider: String { t("Provider", "Fournisseur", "Proveedor", "提供商", "Provedor", "Anbieter") }
    static var apiKey: String { t("API Key", "Clé API", "Clave API", "API 密钥", "Chave API", "API-Schlüssel") }
    static var prompt: String { t("Prompt:", "Prompt :", "Prompt:", "提示词：", "Prompt:", "Prompt:") }
    static var resetPromptToDefault: String { t("Reset prompt to default", "Réinitialiser le prompt par défaut", "Restablecer prompt predeterminado", "重置为默认提示词", "Redefinir prompt padrão", "Prompt auf Standard zurücksetzen") }

    // MARK: Setup Window
    static var setupWelcomeTitle: String { t("Welcome to MacWhisperer", "Bienvenue dans MacWhisperer", "Bienvenido a MacWhisperer", "欢迎使用 MacWhisperer", "Bem-vindo ao MacWhisperer", "Willkommen bei MacWhisperer") }
    static var setupWelcomeSubtitle: String { t(
        "MacWhisperer needs two permissions to work correctly.",
        "MacWhisperer a besoin de deux autorisations pour fonctionner correctement.",
        "MacWhisperer necesita dos permisos para funcionar correctamente.",
        "MacWhisperer 需要两项权限才能正常工作。",
        "MacWhisperer precisa de duas permissões para funcionar corretamente.",
        "MacWhisperer benötigt zwei Berechtigungen, um korrekt zu funktionieren."
    )}
    static var setupMicrophoneTitle: String { t("Microphone", "Microphone", "Micrófono", "麦克风", "Microfone", "Mikrofon") }
    static var setupMicrophoneDescription: String { t(
        "Required to capture your voice for transcription.",
        "Requis pour capturer votre voix pour la transcription.",
        "Necesario para capturar tu voz para la transcripción.",
        "需要捕获您的声音以进行转录。",
        "Necessário para capturar sua voz para transcrição.",
        "Erforderlich, um Ihre Stimme für die Transkription aufzuzeichnen."
    )}
    static var setupAccessibilityTitle: String { t("Accessibility", "Accessibilité", "Accesibilidad", "辅助功能", "Acessibilidade", "Bedienungshilfen") }
    static var setupAccessibilityDescription: String { t(
        "Required to type transcribed text at the cursor position in any app.",
        "Requis pour saisir le texte transcrit à la position du curseur dans n'importe quelle app.",
        "Necesario para escribir el texto transcrito en la posición del cursor en cualquier app.",
        "需要在任何应用中的光标位置输入转录文本。",
        "Necessário para digitar o texto transcrito na posição do cursor em qualquer app.",
        "Erforderlich, um transkribierten Text an der Cursorposition in jeder App einzugeben."
    )}
    static var setupGrant: String { t("Grant...", "Autoriser...", "Conceder...", "授权...", "Conceder...", "Erlauben...") }
    static var setupAllGranted: String { t("All permissions granted!", "Toutes les autorisations accordées !", "¡Todos los permisos concedidos!", "所有权限已授予！", "Todas as permissões concedidas!", "Alle Berechtigungen erteilt!") }
    static var setupRestartNote: String { t(
        "After granting Accessibility, you may need to restart the app.",
        "Après avoir accordé l'accessibilité, vous devrez peut-être redémarrer l'app.",
        "Después de conceder accesibilidad, puede que necesites reiniciar la app.",
        "授予辅助功能权限后，您可能需要重新启动应用。",
        "Após conceder acessibilidade, pode ser necessário reiniciar o app.",
        "Nach Erteilung der Bedienungshilfen müssen Sie die App möglicherweise neu starten."
    )}
    static var setupRecheck: String { t("Recheck", "Revérifier", "Revisar", "重新检查", "Reverificar", "Erneut prüfen") }
    static var setupGetStarted: String { t("Get Started", "Commencer", "Comenzar", "开始使用", "Começar", "Loslegen") }
    static var setupSkip: String { t("Skip for now", "Ignorer pour l'instant", "Omitir por ahora", "暂时跳过", "Pular por agora", "Vorerst überspringen") }

    // MARK: Settings - Sidebar section names
    static var sectionLanguages: String { t("Languages", "Langues", "Idiomas", "语言", "Idiomas", "Sprachen") }
    static var sectionTranscription: String { t("Transcription", "Transcription", "Transcripción", "转录", "Transcrição", "Transkription") }
    static var sectionStreaming: String { t("Streaming", "Streaming", "Streaming", "流式传输", "Streaming", "Streaming") }
    static var sectionSupport: String { t("Support", "Assistance", "Soporte", "支持", "Suporte", "Support") }

    // MARK: Settings - General
    static var settingsStartup: String { t("Startup", "Démarrage", "Inicio automático", "开机启动", "Inicialização", "Autostart") }
    static var settingsInputDevice: String { t("Input device", "Périphérique d'entrée", "Dispositivo de entrada", "输入设备", "Dispositivo de entrada", "Eingabegerät") }
    static var settingsInterfaceLanguage: String { t("Interface Language", "Langue de l'interface", "Idioma de la interfaz", "界面语言", "Idioma da interface", "Oberflächensprache") }

    // MARK: Settings - Languages section
    static var settingsShortcut: String { t("Shortcut", "Raccourci", "Atajo", "快捷键", "Atalho", "Kurzbefehl") }
    static var settingsCycleLanguages: String { t("Cycle preferred languages", "Parcourir les langues préférées", "Ciclar idiomas preferidos", "循环切换首选语言", "Ciclar idiomas preferidos", "Sprachen durchschalten") }

    // MARK: Settings - Transcription section
    static var settingsLivePreview: String { t("Live Preview", "Aperçu en direct", "Vista previa en vivo", "实时预览", "Pré-visualização ao vivo", "Live-Vorschau") }
    static var settingsShowWordsAsYouSpeak: String { t("Show words as you speak", "Afficher les mots en temps réel", "Mostrar palabras mientras hablas", "边说边显示文字", "Mostrar palavras enquanto fala", "Wörter beim Sprechen anzeigen") }
    static var settingsHoldToRecord: String { t("Hold to record", "Maintenir pour enregistrer", "Mantener para grabar", "按住录音", "Segurar para gravar", "Halten zum Aufnehmen") }

    // MARK: Settings - Streaming section
    static var settingsEnableLivePreview: String { t("Enable live preview", "Activer l'aperçu en direct", "Activar vista previa en vivo", "启用实时预览", "Ativar pré-visualização ao vivo", "Live-Vorschau aktivieren") }
    static var settingsStreamingModel: String { t("Streaming Model", "Modèle de streaming", "Modelo de streaming", "流式模型", "Modelo de streaming", "Streaming-Modell") }
    static var settingsStatus: String { t("Status", "Statut", "Estado", "状态", "Status", "Status") }
    static var settingsLoadingModel: String { t("Loading model…", "Chargement du modèle…", "Cargando modelo…", "正在加载模型…", "Carregando modelo…", "Modell wird geladen…") }

    // MARK: Settings - Meeting section
    static var settingsToggleRecording: String { t("Toggle recording", "Basculer l'enregistrement", "Alternar grabación", "切换录音", "Alternar gravação", "Aufnahme umschalten") }
    static var settingsSaveTo: String { t("Save to", "Enregistrer dans", "Guardar en", "保存到", "Salvar em", "Speichern in") }
    static var settingsRefineWithAI: String { t("Refine with AI after transcription", "Améliorer avec l'IA après la transcription", "Refinar con IA tras transcribir", "转录后用AI优化", "Refinar com IA após transcrição", "Nach Transkription mit KI verfeinern") }
    static var settingsModelID: String { t("Model ID", "ID du modèle", "ID del modelo", "模型 ID", "ID do modelo", "Modell-ID") }
    static var settingsResetToDefault: String { t("Reset to default", "Réinitialiser", "Restablecer", "重置", "Redefinir", "Zurücksetzen") }

    // MARK: Settings - Permissions section
    static var settingsRequiredPermissions: String { t("Required Permissions", "Autorisations requises", "Permisos requeridos", "必要权限", "Permissões necessárias", "Erforderliche Berechtigungen") }
    static var settingsOpenSetupGuide: String { t("Open setup guide…", "Ouvrir le guide de configuration…", "Abrir guía de configuración…", "打开guía de configuración…", "Abrir guia de configuração…", "Einrichtungshilfe öffnen…") }

    // MARK: Settings - Support section
    static var settingsBugReport: String { t("Bug Report", "Signalement de bug", "Reporte de error", "错误报告", "Relatório de bug", "Fehlerbericht") }
    static var settingsBugDescription: String { t("Description", "Description", "Descripción", "描述", "Descrição", "Beschreibung") }
    static var settingsSendBugReport: String { t("Send Bug Report", "Envoyer le rapport", "Enviar reporte", "发送错误报告", "Enviar relatório", "Fehlerbericht senden") }

    // MARK: Settings - Permissions
    static var settingsPermissions: String { t("Permissions", "Autorisations", "Permisos", "权限", "Permissões", "Berechtigungen") }
    static var settingsMicrophone: String { t("Microphone", "Microphone", "Micrófono", "麦克风", "Microfone", "Mikrofon") }
    static var settingsAccessibility: String { t("Accessibility", "Accessibilité", "Accesibilidad", "辅助功能", "Acessibilidade", "Bedienungshilfen") }
    static var settingsShowSetupGuide: String { t("Show setup guide...", "Afficher le guide de configuration...", "Mostrar guía de configuración...", "显示设置指南...", "Mostrar guia de configuração...", "Einrichtungshilfe anzeigen...") }

    // MARK: Menu Bar
    static var microphoneNotAuthorized: String { t("Microphone not authorized", "Microphone non autorisé", "Micrófono no autorizado", "麦克风未授权", "Microfone não autorizado", "Mikrofon nicht autorisiert") }
    static var openMicrophoneSettings: String { t("Open Microphone Settings...", "Ouvrir les réglages du microphone...", "Abrir ajustes de micrófono...", "打开麦克风设置...", "Abrir configurações do microfone...", "Mikrofon-Einstellungen öffnen...") }
    static var accessibilityNotAuthorized: String { t("Accessibility not authorized", "Accessibilité non autorisée", "Accesibilidad no autorizada", "辅助功能未授权", "Acessibilidade não autorizada", "Bedienungshilfen nicht autorisiert") }
    static var openAccessibilitySettings: String { t("Open Accessibility Settings...", "Ouvrir les réglages d'accessibilité...", "Abrir ajustes de accesibilidad...", "打开辅助功能设置...", "Abrir configurações de acessibilidade...", "Bedienungshilfen-Einstellungen öffnen...") }
    static var restartApp: String { t("Restart App (required after granting)", "Redémarrer l'app (requis après autorisation)", "Reiniciar app (requerido tras autorizar)", "重启应用（授权后需要）", "Reiniciar app (necessário após autorizar)", "App neu starten (erforderlich nach Genehmigung)") }
    static var processingMeeting: String { t("Processing meeting...", "Traitement de la réunion...", "Procesando reunión...", "正在处理会议...", "Processando reunião...", "Besprechung wird verarbeitet...") }
    static var transcribing: String { t("Transcribing...", "Transcription en cours...", "Transcribiendo...", "正在转录...", "Transcrevendo...", "Transkription läuft...") }
    static var recording: String { t("Recording...", "Enregistrement...", "Grabando...", "正在录音...", "Gravando...", "Aufnahme läuft...") }
    static var loadingModel: String { t("Loading model...", "Chargement du modèle...", "Cargando modelo...", "正在加载模型...", "Carregando modelo...", "Modell wird geladen...") }
    static var ready: String { t("Ready", "Prêt", "Listo", "就绪", "Pronto", "Bereit") }
    static var recheckPermissions: String { t("Recheck Permissions", "Revérifier les autorisations", "Revisar permisos", "重新检查权限", "Reverificar permissões", "Berechtigungen erneut prüfen") }
    static var language: String { t("Language", "Langue", "Idioma", "语言", "Idioma", "Sprache") }
    static var autoDetect: String { t("Auto-detect", "Détection auto", "Detección automática", "自动检测", "Detecção automática", "Automatisch erkennen") }
    static var stopMeetingRecording: String { t("Stop Meeting Recording", "Arrêter l'enregistrement", "Detener grabación", "停止会议录音", "Parar gravação", "Aufnahme stoppen") }
    static var transcribingMeeting: String { t("Transcribing meeting...", "Transcription de la réunion...", "Transcribiendo reunión...", "正在转录会议...", "Transcrevendo reunião...", "Besprechung wird transkribiert...") }
    static var cancelTranscription: String { t("Cancel Transcription", "Annuler la transcription", "Cancelar transcripción", "取消转录", "Cancelar transcrição", "Transkription abbrechen") }
    static var startMeetingRecording: String { t("Start Meeting Recording", "Démarrer l'enregistrement", "Iniciar grabación", "开始会议录音", "Iniciar gravação", "Aufnahme starten") }
    static var settings: String { t("Settings...", "Réglages...", "Ajustes...", "设置...", "Configurações...", "Einstellungen...") }
    static var quitWhisperer: String { t("Quit MacWhisperer", "Quitter MacWhisperer", "Salir de MacWhisperer", "退出 MacWhisperer", "Sair do MacWhisperer", "MacWhisperer beenden") }

    // MARK: Download status
    static func downloadingModel(_ name: String, _ percent: Int) -> String {
        t(
            "Downloading model - \(name) - \(percent)%",
            "Téléchargement du modèle - \(name) - \(percent)%",
            "Descargando modelo - \(name) - \(percent)%",
            "正在下载模型 - \(name) - \(percent)%",
            "Baixando modelo - \(name) - \(percent)%",
            "Modell herunterladen - \(name) - \(percent)%"
        )
    }

    static func recordingMeeting(_ minutes: Int, _ seconds: Int) -> String {
        let time = String(format: "%d:%02d", minutes, seconds)
        return t(
            "Recording meeting \(time)",
            "Enregistrement réunion \(time)",
            "Grabando reunión \(time)",
            "录制会议 \(time)",
            "Gravando reunião \(time)",
            "Besprechung aufnehmen \(time)"
        )
    }

    // MARK: - Resolution

    static var current: AppLanguage = .english

    /// Resolve a string by the current app language.
    /// Parameter order: en, fr, es, zh, pt, de
    private static func t(_ en: String, _ fr: String, _ es: String, _ zh: String, _ pt: String, _ de: String) -> String {
        switch current {
        case .english: en
        case .french: fr
        case .spanish: es
        case .chinese: zh
        case .portuguese: pt
        case .german: de
        }
    }
}
