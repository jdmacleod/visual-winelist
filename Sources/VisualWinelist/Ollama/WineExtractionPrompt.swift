import Foundation

enum WineExtractionPrompt {
    // Primary iteration surface — edit this to improve extraction quality.
    // Evaluated against Tests/VisualWinelistTests/EvalSuite/ before v1 ships.
    static let text = """
        You are analyzing a photo of a restaurant wine list. Extract every wine you can identify.

        Output exactly one JSON object per line (JSONL format). No surrounding array. No markdown. No explanation.

        Each line must be valid JSON with this exact schema:
        {"name":"...","producer":"...","vintage":"...","variety":"...","appellation":"...","price":"...","description":"...","listSection":"...","rawText":"...","confidence":0.95}

        Field rules:
        - name: wine name as printed on the list (required)
        - producer: winery or producer name; often the same as name (null if unclear)
        - vintage: 4-digit year as a string, e.g. "2019" (null if not shown)
        - variety: grape variety or blend, e.g. "Cabernet Sauvignon" (null if not shown)
        - appellation: region or appellation, e.g. "Napa Valley, California" (null if not shown)
        - price: price as printed including currency symbol, e.g. "$48" or "48" (null if not shown)
        - description: any tasting notes or description from the list (null if none)
        - listSection: the section header under which this wine appears, e.g. "Red Wines" or "By the Glass" (null if no section header)
        - rawText: the complete original text for this wine entry as it appears on the list
        - confidence: float from 0.0 to 1.0 — your certainty that name and vintage are correctly extracted. Use 0.9+ for clear text, 0.6-0.8 for partially legible text, below 0.6 for guesses.

        Output ONLY JSON lines. One wine per line. No other text.
        """
}
