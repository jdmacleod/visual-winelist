import type { WineRecord } from '../types/wine';
import { absoluteImageUrl } from '../api/client';

interface WineCardProps {
  wine: WineRecord;
  onClick: () => void;
}

export default function WineCard({ wine, onClick }: WineCardProps) {
  return (
    <button
      onClick={onClick}
      className="group w-full text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-500 rounded-xl"
    >
      <div className="aspect-[3/4] rounded-xl overflow-hidden bg-gradient-to-b from-purple-800 to-purple-950 relative shadow-md group-hover:shadow-lg transition-shadow">
        {wine.image_url ? (
          <img
            src={absoluteImageUrl(wine.image_url)}
            alt={wine.name}
            className="w-full h-full object-cover"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center">
            <span className="text-5xl opacity-20">🍷</span>
          </div>
        )}

        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/10 to-transparent" />

        <div className="absolute bottom-0 left-0 right-0 p-3">
          <p className="text-white text-xs font-semibold leading-tight line-clamp-2">{wine.name}</p>
          {wine.vintage && <p className="text-white/70 text-xs mt-0.5">{wine.vintage}</p>}
        </div>

        {wine.verified && (
          <div className="absolute top-2 right-2 bg-green-500 text-white text-xs w-5 h-5 rounded-full flex items-center justify-center font-bold shadow">
            ✓
          </div>
        )}
      </div>
    </button>
  );
}
