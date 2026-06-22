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
  verified_total: number;
}

export type StatusFilter = 'all' | 'verified' | 'unverified' | 'no_image';
export type SortOption = 'newest' | 'oldest' | 'name_asc' | 'producer_asc' | 'verified';

export interface ImageCandidate {
  url: string;
  thumbnail_url: string;
  title: string;
  source_url: string;
  width: number | null;
  height: number | null;
}
