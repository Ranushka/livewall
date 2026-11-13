import SwiftUI

struct PartnerView: View {
    @EnvironmentObject var model: AppModel
    @State private var text = ""
    @State private var joinCode = ""
    @State private var confirmUnpair = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Group { model.paired ? AnyView(pairedView) : AnyView(pairView) }
                .navigationTitle("Partner")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if model.paired { Button("Unpair", role: .destructive) { confirmUnpair = true } }
                            Button("Delete my data", role: .destructive) { confirmDelete = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .alert("Unpair?", isPresented: $confirmUnpair) {
                    Button("Unpair", role: .destructive) { Task { await model.unpair() } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Notes between you will be deleted for both of you.") }
                .alert("Delete my data?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) { Task { await model.deleteAccount() } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Removes your account and unpairs you. This can't be undone.") }
                .safeAreaInset(edge: .bottom) {
                    if let e = model.error { Text(e).font(.footnote).foregroundStyle(.red).padding(8) }
                }
        }
    }

    private var pairView: some View {
        Form {
            Section("Show your code to your partner") {
                if let c = model.code {
                    Text(c.code).font(.system(size: 40, weight: .bold, design: .monospaced))
                    Text("Valid for 10 minutes").font(.footnote).foregroundStyle(.secondary)
                }
                Button(model.code == nil ? "Get a code" : "New code") { Task { await model.makeCode() } }
            }
            Section("Or enter theirs") {
                TextField("6-digit code", text: $joinCode).keyboardType(.numberPad)
                Button("Pair") { Task { await model.join(joinCode) } }
                    .disabled(joinCode.count != 6)
            }
            Section { Button("Check if paired") { Task { await model.refresh() } } }
        }
    }

    private var pairedView: some View {
        VStack(spacing: 0) {
            List(model.notes) { n in
                VStack(alignment: n.mine ? .trailing : .leading, spacing: 2) {
                    Text(n.text).padding(10)
                        .background(n.mine ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15), in: .rect(cornerRadius: 12))
                    Text(n.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: n.mine ? .trailing : .leading)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .refreshable { await model.refresh() }
            HStack {
                TextField("Write a note (\(100 - text.count) left)", text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
                Button("Send") {
                    let t = text
                    Task { if await model.send(t) { text = "" } }
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || text.count > 100)
            }
            .padding()
        }
    }
}
