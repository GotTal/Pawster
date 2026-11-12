import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var pairing: PairingService
    @ObservedObject var guide: PairingGuide
    @State private var showImporter = false
    @State private var importingPair = false
    @State private var pendingReceipt: TransactionReceipt?
    @State private var rollback = false
    @State private var confirmReceipt = false
    @State private var logFile: URL?
    var locked: Bool { model.busy || pairing.running }
    var body: some View {
        TabView {
            NavigationStack { wallpapers }.tabItem { Label("壁纸", systemImage: "photo.on.rectangle") }
            NavigationStack { connection }.tabItem { Label("连接", systemImage: "link") }
            NavigationStack { history }.tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
            NavigationStack { diagnostics }.tabItem { Label("诊断", systemImage: "list.bullet.rectangle") }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if guide.phase != .idle {
                GuidePreview(guide: guide)
                    .aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: 360)
                    .padding(.vertical, 8).frame(maxWidth: .infinity).background(.background)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                if importingPair { do { try pairing.importCredentials(url) } catch { model.error = error.localizedDescription } }
                else { model.importWallpaper(url) }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .sheet(item: $model.plan) { plan in
            NavigationStack {
                List {
                    Section("本次操作") {
                        LabeledContent("注入引擎", value: plan.engine.rawValue)
                        LabeledContent("新增目录", value: "\(plan.items.count) 个")
                        Text("保留原壁纸；不覆盖已有描述文件。注册刷新在写入后单独执行。")
                    }
                    Section("目标容器") { Text(plan.container.path).font(.caption).textSelection(.enabled) }
                    Section("写入目标") { ForEach(plan.items) { item in Text(item.destinationRelative).font(.caption) } }
                    Section { Button("确认注入") { model.plan = nil; model.install(plan) }.buttonStyle(.borderedProminent) }
                }
                .navigationTitle("检查注入计划")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { model.plan = nil } } }
            }
        }
        .alert("操作提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("知道了") { model.error = nil } } message: { Text(model.error ?? "") }
        .confirmationDialog(rollback ? "撤回这次注入？" : "备份并刷新壁纸注册？", isPresented: $confirmReceipt, titleVisibility: .visible) {
            Button(rollback ? "撤回本次内容" : "备份并合并注册偏好", role: rollback ? .destructive : nil) {
                if let receipt = pendingReceipt { model.updateReceipt(receipt, rollback: rollback) }
            }
        } message: {
            Text(rollback ? "仅处理本次记录中的目录和注册偏好；内容被其他操作修改时会停止。" : "将备份并合并 PosterBoard 容器内的注册偏好，不清空 Collections。系统是否显示壁纸仍需实际检查。")
        }
    }
    private var operationStatus: some View {
        Section {
            if model.busy { ProgressView(); Button("取消当前操作", role: .cancel) { model.cancel() } }
            Text(model.status).font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var wallpapers: some View {
        List {
            Section {
                Label("喵贴 Pawster", systemImage: "sparkles").font(.title2.bold())
                Text("将 Collections 壁纸包加入系统壁纸。首次使用请先完成连接与只读检查。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Button("导入 .tendies", systemImage: "square.and.arrow.down") { importingPair = false; showImporter = true }.disabled(locked)
            }
            Section("本地壁纸 · \(model.packs.count)") {
                if model.packs.isEmpty { Text("尚未导入壁纸。支持现有 StudyFriends Collections 包。").foregroundStyle(.secondary) }
                ForEach(model.packs) { pack in
                    Button {
                        if model.selected.contains(pack.id) { model.selected.remove(pack.id) } else { model.selected.insert(pack.id) }
                    } label: {
                        HStack(spacing: 12) {
                            if let preview = pack.preview, let image = UIImage(contentsOfFile: AppFiles.packs.appendingPathComponent(pack.directory).appendingPathComponent(preview).path) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 54, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                            } else { Image(systemName: "photo").frame(width: 54, height: 72) }
                            VStack(alignment: .leading) { Text(pack.name).foregroundStyle(.primary); Text("\(pack.descriptors.count) 个描述文件").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: model.selected.contains(pack.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }.disabled(locked)
                }
            }
            Section {
                Button("预览注入计划", systemImage: "checklist") { model.preview() }
                    .disabled(locked || model.selected.isEmpty || !pairing.hasCredentials)
            }
            operationStatus
        }.navigationTitle("壁纸")
    }
    private var connection: some View {
        List {
            Section("配对文件") {
                LabeledContent("状态", value: pairing.hasCredentials ? "已保存，需连接验证" : "尚未配置")
                Button("导入 SideStore 等工具的配对文件") { importingPair = true; showImporter = true }.disabled(locked)
                Text("连接 LocalDevVPN，并保持本机解锁。配对凭据仅保存在本机，不包含在导出日志中。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("本机配对 · iOS 27") {
                if !pairing.running {
                    Button("开始本机配对") { pairing.start() }.disabled(locked || SystemVersion.current.major < 27)
                }
                if pairing.running {
                    if let pin = pairing.pin { Text(pin).font(.largeTitle.monospacedDigit().bold()).textSelection(.enabled); Button("复制配对码") { pairing.copyPIN() } }
                    Button("取消配对", role: .cancel) { pairing.cancel() }
                }
                Text(pairing.status).font(.footnote)
                Text("设置 → 隐私与安全性 → 开发者模式 → 与 Pawster 配对。配对期间离开 App 自动显示小窗和实时配对码；配对成功后显示成功文字，3 秒后自动关闭。").font(.footnote).foregroundStyle(.secondary)
                Text(guide.note).font(.caption).foregroundStyle(.secondary)
                Button("打开本 App 的系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Section("路径与兼容性") {
                TextField("VPN 网关", text: $model.host).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(locked)
                LabeledContent("当前系统", value: SystemVersion.current.text)
                LabeledContent("注入引擎", value: model.engineLabel)
                if SystemVersion.current == .init(major: 27, minor: 0, patch: 0) {
                    Toggle("我已确认当前为 iOS 27.0 beta 4", isOn: $model.confirmedBeta4).disabled(locked)
                }
                Button("自动查询并只读验证路径") { model.discover() }.disabled(locked || !pairing.hasCredentials)
                TextField("PosterBoard 容器根目录", text: $model.manualPath, axis: .vertical).font(.caption).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(locked)
                Button("只读核验手动路径") { model.validateManual() }.disabled(locked || model.manualPath.isEmpty)
                if let container = model.container {
                    Label("身份已核验 · \(container.source)", systemImage: "checkmark.shield")
                    Text("目录结构 \(container.storeVersion)，\(container.extensionIDs.count) 个目标。注入前会重新查询。").font(.caption)
                }
            }
            operationStatus
        }.navigationTitle("连接与配对")
    }
    private var history: some View {
        List {
            if model.receipts.isEmpty { Text("尚无注入记录。所有实际写入都会先保存操作记录。") }
            ForEach(model.receipts) { receipt in
                Section(receipt.createdAt.formatted(date: .abbreviated, time: .shortened)) {
                    Text(receipt.id.uuidString).font(.caption).textSelection(.enabled)
                    LabeledContent("状态", value: stateName(receipt.state))
                    LabeledContent("目标数量", value: "\(receipt.entries.count)")
                    if let refresh = receipt.refresh { LabeledContent("注册刷新", value: refresh.state == "written" ? "文件已校验" : "操作曾中断，请检查或撤回") }
                    if let failure = receipt.failure { Text(failure).foregroundStyle(.red).font(.caption) }
                    if receipt.state == "filesVerified", receipt.refresh == nil {
                        Button("备份并刷新注册") { pendingReceipt = receipt; rollback = false; confirmReceipt = true }.disabled(locked)
                    }
                    if receipt.state != "rolledBack" {
                        Button("撤回这次注入", role: .destructive) { pendingReceipt = receipt; rollback = true; confirmReceipt = true }.disabled(locked)
                    }
                }
            }
            operationStatus
        }.navigationTitle("操作记录")
    }
    private var diagnostics: some View {
        List {
            Section {
                Text("仅导出操作诊断，不导出配对文件和配对码。壁纸是否实际显示需在系统界面确认。").font(.footnote)
                Button("准备诊断日志") { do { logFile = try model.exportLogs() } catch { model.error = error.localizedDescription } }
                if let logFile { ShareLink("分享诊断日志", item: logFile) }
            }
            Section("最近日志") { ForEach(Array(model.logs.enumerated()), id: \.offset) { _, line in Text(line).font(.caption.monospaced()).textSelection(.enabled) } }
        }.navigationTitle("诊断")
    }
    private func stateName(_ raw: String) -> String {
        switch raw { case "writing": return "写入中或曾意外中断"; case "filesVerified": return "文件已校验，图库效果待确认"; case "partial": return "部分完成，可检查并撤回"; case "rolledBack": return "已撤回"; default: return raw }
    }
}
