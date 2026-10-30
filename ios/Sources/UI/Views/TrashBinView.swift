import SwiftUI

#if canImport(UIKit)
import UIKit

/// 垃圾桶（最近刪除）檢視與復原中心 (對齊原廠 vFlat 最近刪除功能)
/// 項目自動保留 30 天，提供單頁即時還原、批次全部復原與徹底清空
public struct TrashBinView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel

    @State private var showingEmptyConfirm: Bool = false
    @State private var selectedPageIdToPurge: UUID? = nil

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            Group {
                if viewModel.trashPages.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "trash")
                            .font(.system(size: 64))
                            .foregroundColor(.gray.opacity(0.4))
                        Text("垃圾桶為空")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                        Text("刪除的頁面將保留在垃圾桶 30 天，在此期間您可以隨時將它們還原。")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        Section(
                            header: Text("已刪除頁面 (\(viewModel.trashCount) 頁)"),
                            footer: Text("這些頁面會在 30 天後自動永久清除。點擊「還原」可立即復原至文件清單。")
                        ) {
                            ForEach(viewModel.trashPages) { item in
                                HStack(spacing: 14) {
                                    if let thumb = viewModel.pageStore.thumbnail(for: item.page, maxPixel: 160) {
                                        Image(uiImage: thumb)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 54, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.1), lineWidth: 1))
                                    } else {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(white: 0.92))
                                            .frame(width: 54, height: 72)
                                            .overlay(Image(systemName: "doc.text").foregroundColor(.gray))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.page.ocrText?.prefix(30).replacingOccurrences(of: "\n", with: " ") ?? "掃描文件頁")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Text("剩餘 \(item.daysRemaining) 天後自動清除")
                                            .font(.system(size: 12))
                                            .foregroundColor(.orange)

                                        Text(item.deletedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button("還原") {
                                        withAnimation {
                                            viewModel.restorePageFromTrash(id: item.id)
                                        }
                                    }
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.22, green: 0.72, blue: 0.62))
                                    .clipShape(Capsule())
                                }
                                .padding(.vertical, 4)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        viewModel.permanentlyDeleteTrashPage(id: item.id)
                                    } label: {
                                        Label("永久刪除", systemImage: "trash.slash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("垃圾桶 (最近刪除)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }

                if !viewModel.trashPages.isEmpty {
                    ToolbarItemGroup(placement: .confirmationAction) {
                        Menu("操作") {
                            Button("全部還原") {
                                withAnimation {
                                    viewModel.restoreAllFromTrash()
                                }
                            }
                            Button(role: .destructive) {
                                showingEmptyConfirm = true
                            } label: {
                                Text("清空垃圾桶")
                            }
                        }
                    }
                }
            }
            .alert("清空垃圾桶？", isPresented: $showingEmptyConfirm) {
                Button("取消", role: .cancel) {}
                Button("徹底清空", role: .destructive) {
                    withAnimation {
                        viewModel.emptyTrash()
                    }
                }
            } message: {
                Text("此操作將永久抹除垃圾桶中的所有頁面與圖片檔案，無法撤銷。")
            }
        }
    }
}
#endif
