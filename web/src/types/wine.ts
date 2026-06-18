export interface WineRecord {
  wine_id: string;
  name: string;
  producer: string | null;
  vintage: string | null;
  variety: string | null;
  appellation: string | null;
  tasting_note: string | null;
  pairings: string[];
  verified: boolean;
  image_url: string | null;
}

export interface SearchResponse {
  results: WineRecord[];
  total: number;
  page: number;
  page_size: number;
}
