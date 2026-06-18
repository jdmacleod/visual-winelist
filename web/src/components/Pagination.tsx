interface PaginationProps {
  page: number;
  totalPages: number;
  onPageChange: (page: number) => void;
}

export default function Pagination({ page, totalPages, onPageChange }: PaginationProps) {
  return (
    <div className="flex items-center justify-center gap-3 mt-8 pb-2">
      <button
        onClick={() => onPageChange(page - 1)}
        disabled={page <= 1}
        className="px-4 py-2 text-sm border border-stone-300 rounded-lg disabled:opacity-40 hover:bg-stone-50 disabled:hover:bg-transparent transition-colors"
      >
        ← Previous
      </button>
      <span className="text-sm text-stone-500">
        Page {page} of {totalPages}
      </span>
      <button
        onClick={() => onPageChange(page + 1)}
        disabled={page >= totalPages}
        className="px-4 py-2 text-sm border border-stone-300 rounded-lg disabled:opacity-40 hover:bg-stone-50 disabled:hover:bg-transparent transition-colors"
      >
        Next →
      </button>
    </div>
  );
}
