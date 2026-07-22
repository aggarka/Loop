//
//  BusinessCardScanView.swift
//  Loop
//
//  Scans a business card with on-device text recognition (VisionKit), parses the
//  recognized lines into a draft, and presents it for review before saving.
//  Falls back to manual entry when scanning is unavailable (e.g. camera denied
//  or unsupported device) — Requirement 10.
//

import SwiftUI
import VisionKit

struct BusinessCardScanView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var recognizedLines: [String] = []
    @State private var reviewDraft: PersonDraft?
    @State private var showManualFallback = false

    private var isScanningAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if isScanningAvailable {
                    scanner
                } else {
                    unavailable
                }
            }
            .navigationTitle("Scan Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $reviewDraft) { draft in
                PersonEditView(prefill: draft)
            }
            .sheet(isPresented: $showManualFallback) {
                PersonEditView()
            }
        }
    }

    private var scanner: some View {
        ZStack(alignment: .bottom) {
            CardScannerView { lines in
                recognizedLines = lines
            }
            .ignoresSafeArea()

            Button {
                reviewDraft = BusinessCardParser.parse(lines: recognizedLines)
            } label: {
                Text("Use Scanned Info")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .disabled(recognizedLines.isEmpty)
        }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("Scanning Unavailable", systemImage: "camera.fill")
        } description: {
            Text("Camera scanning isn't available. You can add this person manually instead.")
        } actions: {
            Button("Add Manually") { showManualFallback = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Makes `PersonDraft` presentable via `.sheet(item:)`.
extension PersonDraft: Identifiable {
    var id: String { "\(name)-\(email ?? "")-\(phone ?? "")" }
}

/// Wraps VisionKit's `DataScannerViewController` for on-device text recognition.
private struct CardScannerView: UIViewControllerRepresentable {
    var onLines: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLines: onLines) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onLines: ([String]) -> Void

        init(onLines: @escaping ([String]) -> Void) {
            self.onLines = onLines
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            emit(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            emit(allItems)
        }

        private func emit(_ items: [RecognizedItem]) {
            let lines: [String] = items.compactMap { item in
                if case let .text(text) = item { return text.transcript }
                return nil
            }
            onLines(lines)
        }
    }
}
