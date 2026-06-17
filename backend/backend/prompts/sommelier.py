from backend.models.wine import WineObject


def make_sommelier_prompt(wine: WineObject) -> str:
    parts: list[str] = []
    if wine.producer and wine.producer.lower() != wine.name.lower():
        parts.append(f'"{wine.name}" by {wine.producer}')
    else:
        parts.append(f'"{wine.name}"')
    if wine.vintage:
        parts.append(wine.vintage)
    if wine.variety:
        parts.append(wine.variety)
    if wine.appellation:
        parts.append(f"({wine.appellation})")

    wine_desc = " ".join(parts)

    return (
        f"Wine: {wine_desc}\n\n"
        "Respond with ONLY valid JSON — no explanation, no markdown:\n"
        '{"tasting_note": "Two sentences about this wine\'s flavor profile and style.", '
        '"pairings": ["food1", "food2", "food3"]}'
    )
