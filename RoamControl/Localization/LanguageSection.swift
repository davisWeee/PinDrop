import SwiftUI

/// Settings section that switches the app language immediately (no relaunch).
struct LanguageSection: View {
    private let languageSettings = LanguageSettings.shared

    var body: some View {
        Section {
            Picker("Language", selection: selection) {
                ForEach(AppLanguage.allCases) { language in
                    if let name = language.nativeName {
                        Text(verbatim: name).tag(language)
                    } else {
                        Text("System Default").tag(language)
                    }
                }
            }
        } header: {
            Text("Language")
        } footer: {
            Text("Changes the language of PinDrop immediately. System prompts follow after the next launch.")
        }
    }

    private var selection: Binding<AppLanguage> {
        Binding(
            get: { languageSettings.selection },
            set: { languageSettings.select($0) }
        )
    }
}
