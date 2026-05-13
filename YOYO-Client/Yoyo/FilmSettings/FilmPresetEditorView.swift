import simd
import SwiftUI

struct FilmPresetEditorView: View {
    let presetIndex: Int
    var onDismiss: () -> Void
    @ObservedObject private var debugManager = FilmPresetDebugManager.shared

    @State private var draft: FilmPreset?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.trailing, 4)

                Text(draft?.name ?? "Film Preset")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: reset) {
                    Text("Reset")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(4)
                }

                Button(action: copyConfig) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .padding(8)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 4)

            ScrollView(.horizontal, showsIndicators: true) {
                if let draft {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 16) {
                            Text("Exposure").font(.caption).bold().foregroundColor(.gray)

                            ParamSlider(title: "Exposure", subtitle: "曝光", description: "调整画面整体明暗。\nAdjusts the overall brightness of the image.", value: Binding(
                                get: { draft.negativeExposure },
                                set: { val in update { $0 = $0.copy(negativeExposure: val) } }
                            ), range: -1.0 ... 1.0)

                            ParamSlider(title: "Gamma", subtitle: "显影伽马", description: "控制显影反差系数。值越低反差越大（画面深沉），值越高反差越小（画面明亮）。\nControls development gamma. Lower values increase contrast (darker); higher values decrease contrast (brighter).", value: Binding(
                                get: { draft.developmentGamma },
                                set: { val in update { $0 = $0.copy(developmentGamma: val) } }
                            ), range: 0.0 ... 2.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Contrast").font(.caption).bold().foregroundColor(.gray)

                            ParamSlider(title: "Contrast", subtitle: "打印对比度", description: "调节相纸打印阶段的S曲线对比度。模拟相纸硬度号数。\nAdjusts the S-curve contrast during printing. Simulates photo paper grades.", value: Binding(
                                get: { draft.printContrast },
                                set: { val in update { $0 = $0.copy(printContrast: val) } }
                            ), range: 0.0 ... 1.5)

                            ParamSlider(title: "Warmth", subtitle: "暖调", description: "调节画面色温，偏暖（黄/橙）或偏冷（蓝）。\nAdjusts color temperature towards warm (yellow/orange) or cool (blue).", value: Binding(
                                get: { draft.printWarmth },
                                set: { val in update { $0 = $0.copy(printWarmth: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Color Density").font(.caption).bold().foregroundColor(.gray)

                            ParamSlider(title: "Dye Density", subtitle: "染料密度", description: "模拟胶片染料云的堆积密度。越高色彩越浓郁油润（减色法特性），越低越清淡。\nSimulates dye cloud density. Higher values create richer, oily colors (subtractive color); lower values look washed out.", value: Binding(
                                get: { draft.dyeDensity },
                                set: { val in update { $0 = $0.copy(dyeDensity: val) } }
                            ), range: 0.0 ... 2.0)

                            ParamSlider(title: "Crosstalk", subtitle: "层间串扰", description: "模拟乳剂层之间的化学串色。这是胶片所谓“有机感”和“色彩融合”的重要来源。\nSimulates chemical crosstalk between emulsion layers. A key source of the 'organic' film look.", value: Binding(
                                get: { draft.colorCrosstalk },
                                set: { val in update { $0 = $0.copy(colorCrosstalk: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Highlight/Shadow").font(.caption).bold().foregroundColor(.gray)

                            ParamSlider(title: "Rolloff", subtitle: "高光滚降", description: "柔化高光过渡，防止亮部死白。\nSoftens highlight transitions to prevent harsh clipping.", value: Binding(
                                get: { draft.highlightRolloff },
                                set: { val in update { $0 = $0.copy(highlightRolloff: val) } }
                            ), range: 0.0 ... 1.0)

                            ParamSlider(title: "Shadow Lift", subtitle: "暗部提升", description: "提亮阴影细节，模拟胶片宽容度。\nBrightens shadows to recover details, simulating film latitude.", value: Binding(
                                get: { draft.shadowLift },
                                set: { val in update { $0 = $0.copy(shadowLift: val) } }
                            ), range: 0.0 ... 1.0)

                            ParamSlider(title: "Adjacency", subtitle: "邻际效应", description: "增强边缘对比度，提升锐度。\nEnhances edge contrast for sharpness.", value: Binding(
                                get: { draft.adjacencyStrength },
                                set: { val in update { $0 = $0.copy(adjacencyStrength: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Layer Speeds").font(.caption).bold().foregroundColor(.gray)
                            SIMD3Sliders(title: "Speeds (RGB)", subtitle: "感光层速度", description: "模拟RGB三层乳剂的感光速度差异。这是导致胶片特征性色偏（如暗部偏青/高光偏暖）的核心原因。\nSimulates speed differences between RGB emulsion layers. The core reason for characteristic film casts.", value: Binding(
                                get: { draft.layerSpeeds },
                                set: { val in update { $0 = $0.copy(layerSpeeds: val) } }
                            ), range: 0.5 ... 1.5)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Crossovers").font(.caption).bold().foregroundColor(.gray)
                            SIMD3Sliders(title: "X-Over (L/M/H)", subtitle: "串扰阈值", description: "定义色彩串扰生效的亮度阈值。决定了色彩偏移主要发生在阴影、中间调还是高光。\nDefines brightness thresholds for color crosstalk. Determines where color shifts occur (shadows/mids/highlights).", value: Binding(
                                get: { draft.layerCrossovers },
                                set: { val in update { $0 = $0.copy(layerCrossovers: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Halation Power").font(.caption).bold().foregroundColor(.gray)

                            ParamSlider(title: "Strength", subtitle: "光晕强度", description: "模拟强光穿透乳剂层并在片基反射形成的光晕。常见于高光边缘。\nSimulates light penetrating the emulsion and reflecting off the base. Visible around highlights.", value: Binding(
                                get: { draft.halationStrength },
                                set: { val in update { $0 = $0.copy(halationStrength: val) } }
                            ), range: 0.0 ... 5.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Halation Core").font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: "Tint Core", subtitle: "核心色调", description: "光晕中心区域的颜色。\nColor of the halation core.", value: Binding(
                                get: { draft.halationTintCore },
                                set: { val in update { $0 = $0.copy(halationTintCore: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Halation Mid").font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: "Tint Mid", subtitle: "中间色调", description: "光晕过渡区域的颜色。\nColor of the halation mid-tones.", value: Binding(
                                get: { draft.halationTintMid },
                                set: { val in update { $0 = $0.copy(halationTintMid: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Halation Edge").font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: "Tint Edge", subtitle: "边缘色调", description: "光晕外缘的颜色。\nColor of the halation edge.", value: Binding(
                                get: { draft.halationTintEdge },
                                set: { val in update { $0 = $0.copy(halationTintEdge: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Mixer Red").font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: "Red Out (RGB)", subtitle: "红通道混合", description: "调节红色通道的色彩构成。\nAdjusts the color composition of the Red channel.", value: Binding(
                                get: { draft.channelMixerRed },
                                set: { val in update { $0 = $0.copy(channelMixerRed: val) } }
                            ), range: -0.5 ... 1.5)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Mixer Green").font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: "Green Out (RGB)", subtitle: "绿通道混合", description: "调节绿色通道的色彩构成。\nAdjusts the color composition of the Green channel.", value: Binding(
                                get: { draft.channelMixerGreen },
                                set: { val in update { $0 = $0.copy(channelMixerGreen: val) } }
                            ), range: -0.5 ... 1.5)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text("Mixer Blue").font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: "Blue Out (RGB)", subtitle: "蓝通道混合", description: "调节蓝色通道的色彩构成。\nAdjusts the color composition of the Blue channel.", value: Binding(
                                get: { draft.channelMixerBlue },
                                set: { val in update { $0 = $0.copy(channelMixerBlue: val) } }
                            ), range: -0.5 ... 1.5)
                        }
                        .frame(width: 140)
                    }
                    .padding([.horizontal, .bottom])
                }
            }
        }
        .background(Material.ultraThinMaterial)
        .onAppear {
            loadPreset()
        }
        .onChange(of: presetIndex) { _, newValue in
            loadPreset(newValue)
        }
    }

    private func loadPreset(_ index: Int? = nil) {
        let idx = index ?? presetIndex
        if FilmPreset.all.indices.contains(idx) {
            let original = FilmPreset.all[idx]
            draft = debugManager.getPreset(original: original, index: idx)
        }
    }

    private func update(_ modifier: (inout FilmPreset) -> Void) {
        guard var current = draft else { return }
        modifier(&current)
        draft = current
        debugManager.updatePreset(index: presetIndex, preset: current)
    }

    private func reset() {
        debugManager.resetPreset(index: presetIndex)
        loadPreset()
    }

    private func copyConfig() {
        guard let draft else { return }
        debugManager.copyConfigToClipboard(preset: draft)
    }
}

struct ParamSlider: View {
    let title: String
    let subtitle: String
    let description: String
    @Binding var value: Float
    let range: ClosedRange<Float>

    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: { showDetail = true }) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                        Image(systemName: "info.circle")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)
                .alert(isPresented: $showDetail) {
                    Alert(
                        title: Text("\(title) / \(subtitle)"),
                        message: Text(description),
                        dismissButton: .default(Text("OK"))
                    )
                }

                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(.yellow)
            }
            Slider(value: $value, in: range)
                .tint(.yellow)
        }
    }
}

struct SIMD3Sliders: View {
    let title: String
    let subtitle: String
    let description: String
    @Binding var value: SIMD3<Float>
    let range: ClosedRange<Float>

    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { showDetail = true }) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                    Image(systemName: "info.circle").font(.system(size: 8)).foregroundColor(.gray.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            .alert(isPresented: $showDetail) {
                Alert(
                    title: Text("\(title) / \(subtitle)"),
                    message: Text(description),
                    dismissButton: .default(Text("OK"))
                )
            }

            ParamSlider(title: "R / Low", subtitle: "红/低", description: "红色通道或低频分量\nRed channel or Low frequency component", value: Binding(
                get: { value.x },
                set: {
                    var newValue = value
                    newValue.x = $0
                    value = newValue
                }
            ), range: range)

            ParamSlider(title: "G / Mid", subtitle: "绿/中", description: "绿色通道或中频分量\nGreen channel or Mid frequency component", value: Binding(
                get: { value.y },
                set: {
                    var newValue = value
                    newValue.y = $0
                    value = newValue
                }
            ), range: range)

            ParamSlider(title: "B / High", subtitle: "蓝/高", description: "蓝色通道或高频分量\nBlue channel or High frequency component", value: Binding(
                get: { value.z },
                set: {
                    var newValue = value
                    newValue.z = $0
                    value = newValue
                }
            ), range: range)
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}
