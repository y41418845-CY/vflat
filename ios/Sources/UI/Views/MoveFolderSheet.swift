import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 移動頁面至指定資料夾之彈窗 (對齊原廠 MoveFolderViewController)
public struct MoveFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel
    let pageIds: Set<UUID>

    @State private var showingCreateFolderAlert: Bool = false
    @State private var newFolderName: String = ""

    public init(viewModel: ScannerViewModel, pageIds: Set<UUID>) {
        self.viewModel = viewModel
        self.pageIds = pageIds
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: {
                        newFolderName = ""
                        showingCreateFolderAlert = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 20))
                                .foregroundColor(Color(red: 0.08, green: 0.78, blue: 0.44))
                            Text("新增資料夾")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("選擇目標資料夾")) {
                    ForEach(viewModel.pageStore.folders) { folder in
                        let isCurrent = (folder.id == viewModel.pageStore.currentFolderId)
                        Button(action: {
                            viewModel.pageStore.move(pageIds: pageIds, to: folder.id)
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: isCurrent ? "folder.fill" : "folder")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color(red: 0.08, green: 0.78, blue: 0.44))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("\(viewModel.pageStore.pages(in: folder.id).count) 頁")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if isCurrent {
                                    Text("目前")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.gray.opacity(0.15))
                                        .cornerRadius(6)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("移動到資料夾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert("新增資料夾", isPresented: $showingCreateFolderAlert) {
                TextField("資料夾名稱", text: $newFolderName)
                Button("取消", role: .cancel) {}
                Button("建立") {
                    let created = viewModel.pageStore.createFolder(name: newFolderName)
                    viewModel.pageStore.move(pageIds: pageIds, to: created.id)
                    dismiss()
                }
            }
        }
    }
}
