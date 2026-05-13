import SwiftUI

// MARK: - Import Code UI Components

struct AutoFocusTextField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.keyboardType = .asciiCapable
        textField.autocapitalizationType = .allCharacters
        textField.autocorrectionType = .no
        textField.textColor = .clear
        textField.tintColor = .clear
        textField.backgroundColor = .clear
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidChange), for: .editingChanged)

        // Auto focus
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }

        return textField
    }

    func updateUIView(_ uiView: UITextField, context _: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textFieldDidChange(_ textField: UITextField) {
            var newText = textField.text ?? ""
            // Limit to 6 characters
            if newText.count > 6 {
                newText = String(newText.prefix(6))
                textField.text = newText
            }
            // Ensure uppercase
            let uppercased = newText.uppercased()
            if newText != uppercased {
                newText = uppercased
                textField.text = newText
            }
            text = newText
        }
    }
}

struct SixDigitCodeInputView: View {
    @Binding var code: String
    var isError: Bool

    var body: some View {
        ZStack {
            // Hidden TextField for input with auto-focus
            AutoFocusTextField(text: $code)
                .frame(width: 1, height: 1)
                .opacity(0.01) // Keep it interactive but invisible

            // Visual representation
            HStack(spacing: 8) {
                ForEach(0 ..< 6) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.2))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(borderColor(for: index), lineWidth: 2)
                            )

                        if index < code.count {
                            let charIndex = code.index(code.startIndex, offsetBy: index)
                            Text(String(code[charIndex]))
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        // Tapping anywhere on the visual representation should focus the text field
        // Since AutoFocusTextField is always there, we might need a way to re-focus if lost.
        // But for this simple overlay, it usually keeps focus or regains it on appear.
    }

    private func borderColor(for index: Int) -> Color {
        if isError {
            return .red
        }
        if index == code.count {
            return .accentColor
        }
        return .clear
    }
}

struct ImportCodeOverlay: View {
    @Binding var isPresented: Bool
    @Binding var code: String
    @Binding var isImporting: Bool
    @Binding var error: String?
    let onImport: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isImporting {
                        isPresented = false
                        error = nil
                    }
                }

            VStack(spacing: 24) {
                Text(String.automationImportTitle.localized)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(String.automationImportInputCode.localized)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.top, -16)

                SixDigitCodeInputView(code: $code, isError: error != nil)

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                HStack(spacing: 16) {
                    Button(action: {
                        isPresented = false
                        code = ""
                        error = nil
                    }) {
                        Text(String.commonCancel.localized)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(white: 0.2))
                            .cornerRadius(25)
                    }

                    Button(action: onImport) {
                        if isImporting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text(String.automationImportConfirm.localized)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(code.count == 6 ? Color.accentColor : Color.gray.opacity(0.5))
                    .cornerRadius(25)
                    .disabled(code.count != 6 || isImporting)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .cornerRadius(24)
            .padding(.horizontal, 32)
            .shadow(radius: 20)
        }
        .trackScreen(name: "AutomationImportOverlay")
    }
}
