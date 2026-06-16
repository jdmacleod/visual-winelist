import Foundation
import Combine

@MainActor
class WineListViewModel: ObservableObject {
    @Published var wines: [WineState] = []
    @Published var isScanning = false
    @Published var scanMessage = ""
    @Published var errorMessage: String?
    @Published var selectedWine: WineObject?

    private let ollamaClient = OllamaClient()
    private let braveClient: BraveSearchClient
    private let imageCache = ImageCache()

    init(braveAPIKey: String) {
        self.braveClient = BraveSearchClient(apiKey: braveAPIKey)
    }

    // First scan: clears the grid and populates from scratch.
    func scan(photoData: Data) async {
        wines = []
        await performScan(photoData: photoData, appending: false)
    }

    // Multi-page scan: appends new wines (deduplicates by name+vintage).
    func appendScan(photoData: Data) async {
        await performScan(photoData: photoData, appending: true)
    }

    func clear() {
        wines = []
        selectedWine = nil
        errorMessage = nil
    }

    // MARK: - Private

    private func performScan(photoData: Data, appending: Bool) async {
        isScanning = true
        scanMessage = "Reading wine list…"
        errorMessage = nil

        do {
            var extractedCount = 0
            for try await wine in ollamaClient.extractWines(from: photoData) {
                // Deduplication: skip wines already in the grid
                guard !wines.contains(where: { $0.wine == wine }) else { continue }

                extractedCount += 1
                wines.append(.extracting(wine))
                scanMessage = "\(wines.count) wine\(wines.count == 1 ? "" : "s") found…"

                // Kick off image fetch without blocking the extraction stream
                Task { await fetchImage(for: wine) }
            }
            if extractedCount == 0 && !appending {
                errorMessage = "No wines found — try a flatter angle or better lighting"
            }
        } catch OllamaError.connectionRefused {
            errorMessage = "Ollama is not running. Start it with:\n  ollama serve"
        } catch OllamaError.noWinesFound {
            errorMessage = "No wines found — try a flatter angle or better lighting"
        } catch {
            errorMessage = "Couldn't read this list — \(error.localizedDescription)"
        }

        isScanning = false
        scanMessage = ""
    }

    private func fetchImage(for wine: WineObject) async {
        guard let idx = wines.firstIndex(where: { $0.wine == wine }) else { return }

        wines[idx] = .fetchingImage(wine)

        if let cached = await imageCache.fetch(for: wine) {
            wines[idx] = .ready(wine, cached)
            return
        }

        if let data = await braveClient.fetchBottleImage(for: wine) {
            await imageCache.store(data, for: wine)
            wines[idx] = .ready(wine, data)
        } else {
            wines[idx] = .placeholder(wine)
        }
    }
}
