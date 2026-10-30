import SwiftUI

struct TrashBinView: View {
    @EnvironmentObject var vm: ScannerViewModel

    var body: some View {
        NavigationView {
            List {
                Section("最近 30 天內刪除的頁面") {
                    ForEach(vm.pageStore.trashPages) { tp in
                        HStack {
                            if let img = vm.pageStore.thumbnail(for: tp.page) {
                                Image(uiImage: img).resizable().frame(width: 40, height: 50)
                            }
                            VStack(alignment: .leading) {
                                Text("第 \(vm.pageStore.pages.count + 1) 頁")
                                Text("還有 \(tp.daysUntilExpiry) 天過期").font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            Button("還原") { vm.pageStore.restore(id: tp.id) }
                        }
                    }
                }
            }
            .navigationTitle("垃圾桶")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("全部還原") { vm.pageStore.restoreAll() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("清空", role: .destructive) { vm.pageStore.emptyTrash() }.foregroundColor(.red) }
            }
        }
    }
}
