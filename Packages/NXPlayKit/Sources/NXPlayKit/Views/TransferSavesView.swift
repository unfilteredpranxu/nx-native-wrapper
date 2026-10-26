import SwiftUI

/// Copy a game's save to this Mac from a device, or from this Mac to a device, after seeing which is newer.
struct TransferSavesView: View {
    @Bindable var transfer: SaveTransfer
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Transfer Saves · \(transfer.game.name)").font(.title3.bold())
            controls
            files
            summary
            footer
        }
        .padding(20)
        .frame(width: 640, height: 480)
        .task { await pickFirstDevice() }
        .onChange(of: library.devices) { Task { await pickFirstDevice() } }
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Direction").foregroundStyle(.secondary)
                Picker("Direction", selection: $transfer.direction) {
                    Text("To This Mac").tag(SaveTransfer.Direction.toMac)
                    Text("From This Mac").tag(SaveTransfer.Direction.fromMac)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            GridRow {
                Text("Device").foregroundStyle(.secondary)
                HStack {
                    Picker("Device", selection: $transfer.device) {
                        if library.devices.isEmpty {
                            Text(library.isLoadingDevices ? "Looking for devices…" : "No device")
                                .tag(Device?.none)
                        }
                        ForEach(library.devices) { device in
                            Text("\(device.name) · \(device.model)").tag(Device?.some(device))
                        }
                    }
                    .labelsHidden()
                    .onChange(of: transfer.device) { Task { await transfer.loadDevice() } }
                    if transfer.apps.count > 1 {
                        Picker("App", selection: $transfer.app) {
                            ForEach(transfer.apps) { app in
                                Text(app.bundleID).tag(DeviceApp?.some(app))
                            }
                        }
                        .labelsHidden()
                        .onChange(of: transfer.app) { Task { await transfer.loadDeviceFiles() } }
                    }
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await transfer.loadDevice() }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(transfer.device == nil || transfer.isBusy)
                    .help(
                        transfer.device == nil
                            ? "Look for devices again" : "Read the device's save again"
                    )
                    .disabled(transfer.isBusy || library.isLoadingDevices)
                }
            }
        }
    }

    @ViewBuilder private var files: some View {
        let rows = transfer.comparison.rows
        if library.devices.isEmpty {
            NoDeviceView(isLooking: library.isLoadingDevices)
        } else if transfer.phase == .loading, transfer.deviceFiles == nil {
            ProgressView("Reading the save on the device…").frame(
                maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView(
                "No Save Files", systemImage: "externaldrive",
                description: Text("Neither this Mac nor the device has a save for this game yet.")
            )
            .frame(maxHeight: .infinity)
        } else {
            Table(rows) {
                TableColumn("File") { row in
                    Text(row.path).lineLimit(1).truncationMode(.middle).help(row.path)
                }
                TableColumn("This Mac") { row in FileCell(file: row.mac) }
                    .width(min: 120, ideal: 130)
                TableColumn(transfer.device?.name ?? "Device") { row in FileCell(file: row.device) }
                    .width(min: 120, ideal: 130)
                TableColumn("") { row in
                    StatusCell(status: row.status, deviceName: transfer.device?.name ?? "device")
                }
                .width(min: 110, ideal: 130)
            }
        }
    }

    @ViewBuilder private var summary: some View {
        let comparison = transfer.comparison
        let device = transfer.device?.name ?? "the device"
        VStack(alignment: .leading, spacing: 4) {
            if transfer.deviceFiles != nil {
                if comparison.isIdentical {
                    Label("The saves are the same.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else if let newer = comparison.newer, let date = comparison.latest(newer) {
                    Label(
                        "\(newer == .mac ? "This Mac's" : "\(device)'s") save is newer: last change \(date.formatted(.relative(presentation: .named))).",
                        systemImage: "clock")
                }
                if replacesNewer {
                    Label(
                        "This replaces the newer save. The replaced one is kept on this Mac (save-backups).",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
            switch transfer.phase {
            case .done(let message):
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            default: EmptyView()
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            Text("Close the game on this Mac and on the device first.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if transfer.isBusy { ProgressView().controlSize(.small) }
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(copyTitle) { Task { await transfer.copy() } }
                .keyboardShortcut(.defaultAction)
                .disabled(!transfer.canCopy || library.isBusy(transfer.game))
        }
    }

    private var copyTitle: String {
        transfer.direction == .toMac
            ? "Copy to This Mac" : "Copy to \(transfer.device?.name ?? "Device")"
    }

    private var replacesNewer: Bool {
        switch (transfer.direction, transfer.comparison.newer) {
        case (.toMac, .mac?), (.fromMac, .device?): true
        default: false
        }
    }

    private func pickFirstDevice() async {
        guard transfer.device == nil, let first = library.devices.first else { return }
        transfer.device = first  // onChange loads it
    }
}

/// No iPhone or iPad this Mac can reach: what pairing takes. Each Mac pairs with a device on its own, so a
/// phone set up on one Mac is not listed on another until it is paired there too. A newly paired device
/// shows up by itself (the device list refreshes when the app becomes active).
private struct NoDeviceView: View {
    let isLooking: Bool

    var body: some View {
        ContentUnavailableView {
            Label(
                isLooking ? "Looking for Devices…" : "No iPhone or iPad",
                systemImage: "iphone.slash")
        } description: {
            Text(
                """
                Each Mac pairs with a device on its own. Connect it to this Mac with a cable, unlock it and tap Trust. \
                Then open Xcode › Window › Devices and Simulators and wait until Xcode has prepared it; \
                tick Connect via network there to skip the cable next time. \
                Developer Mode must be on (Settings › Privacy & Security).
                """)
        } actions: {
            if isLooking { ProgressView().controlSize(.small) }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct FileCell: View {
    let file: SaveFile?

    var body: some View {
        if let file {
            // the time decides which save is newer: its own line, never truncated; the date and size under it
            VStack(alignment: .leading, spacing: 1) {
                Text(file.modified, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
                    .fixedSize()
                Text(
                    "\(file.modified.formatted(.dateTime.day().month(.abbreviated).year())) · \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .help(file.modified.formatted(date: .complete, time: .complete))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

private struct StatusCell: View {
    let status: SaveComparison.Status
    let deviceName: String

    var body: some View {
        switch status {
        case .same: Badge(text: "Same", color: .secondary)
        case .newer(.mac): Badge(text: "Newer on Mac", color: .blue)
        case .newer(.device): Badge(text: "Newer on device", color: .purple)
        case .only(.mac): Badge(text: "Only on Mac", color: .blue)
        case .only(.device): Badge(text: "Only on device", color: .purple)
        case .differs: Badge(text: "Differs", color: .orange)
        }
    }
}
