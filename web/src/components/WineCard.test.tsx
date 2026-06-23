import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import WineCard from './WineCard';
import type { WineRecord } from '../types/wine';

vi.mock('../api/client', () => ({
  absoluteImageUrl: (url: string) => url,
}));

function makeWine(overrides: Partial<WineRecord> = {}): WineRecord {
  return {
    wine_id: 'test-wine-id',
    name: 'Château Test',
    producer: 'Test Winery',
    vintage: '2020',
    variety: 'Pinot Noir',
    appellation: 'Burgundy',
    tasting_note: null,
    pairings: [],
    verified: false,
    image_url: null,
    ...overrides,
  };
}

test('renders wine name and vintage without image', () => {
  render(<WineCard density={4} wine={makeWine()} onClick={vi.fn()} />);
  expect(screen.getByText('Château Test')).toBeInTheDocument();
  expect(screen.getByText('2020')).toBeInTheDocument();
  expect(screen.queryByRole('img')).not.toBeInTheDocument();
});

test('renders image when image_url is set', () => {
  render(
    <WineCard
      density={4}
      wine={makeWine({ image_url: '/wines/test-wine-id/image' })}
      onClick={vi.fn()}
    />,
  );
  const img = screen.getByRole('img', { name: 'Château Test' });
  expect(img).toHaveAttribute('src', '/wines/test-wine-id/image');
});

test('shows verified badge when wine is verified', () => {
  render(<WineCard density={4} wine={makeWine({ verified: true })} onClick={vi.fn()} />);
  expect(screen.getByText('✓')).toBeInTheDocument();
});

test('does not show verified badge when wine is unverified', () => {
  render(<WineCard density={4} wine={makeWine({ verified: false })} onClick={vi.fn()} />);
  expect(screen.queryByText('✓')).not.toBeInTheDocument();
});

test('calls onClick when card is clicked', async () => {
  const user = userEvent.setup();
  const onClick = vi.fn();
  render(<WineCard density={4} wine={makeWine()} onClick={onClick} />);
  await user.click(screen.getByRole('button'));
  expect(onClick).toHaveBeenCalled();
});

// ---------------------------------------------------------------------------
// Density-driven label visibility
// ---------------------------------------------------------------------------

test('hides name label at density=12 (showName=false)', () => {
  render(<WineCard density={12} wine={makeWine()} onClick={vi.fn()} />);
  expect(screen.queryByText('Château Test')).not.toBeInTheDocument();
  expect(screen.queryByText('2020')).not.toBeInTheDocument();
});

test('hides name label at density=16 (showName=false)', () => {
  render(<WineCard density={16} wine={makeWine()} onClick={vi.fn()} />);
  expect(screen.queryByText('Château Test')).not.toBeInTheDocument();
});

test('shows name and vintage at density=8 (showName=true)', () => {
  render(<WineCard density={8} wine={makeWine()} onClick={vi.fn()} />);
  expect(screen.getByText('Château Test')).toBeInTheDocument();
  expect(screen.getByText('2020')).toBeInTheDocument();
});

test('does not show vintage label when wine has no vintage', () => {
  render(<WineCard density={4} wine={makeWine({ vintage: null })} onClick={vi.fn()} />);
  expect(screen.getByText('Château Test')).toBeInTheDocument();
  // vintage block absent
  expect(screen.queryByText('null')).not.toBeInTheDocument();
});

// ---------------------------------------------------------------------------
// Keyboard navigation
// ---------------------------------------------------------------------------

test('calls onClick when Enter key is pressed on card', async () => {
  const user = userEvent.setup();
  const onClick = vi.fn();
  render(<WineCard density={4} wine={makeWine()} onClick={onClick} />);
  const card = screen.getByRole('button', { name: 'Château Test' });
  card.focus();
  await user.keyboard('{Enter}');
  expect(onClick).toHaveBeenCalled();
});

test('calls onClick when Space key is pressed on card', async () => {
  const user = userEvent.setup();
  const onClick = vi.fn();
  render(<WineCard density={4} wine={makeWine()} onClick={onClick} />);
  const card = screen.getByRole('button', { name: 'Château Test' });
  card.focus();
  await user.keyboard(' ');
  expect(onClick).toHaveBeenCalled();
});

// ---------------------------------------------------------------------------
// Zoom modal
// ---------------------------------------------------------------------------

test('zoom button does not appear when there is no image', () => {
  render(<WineCard density={4} wine={makeWine({ image_url: null })} onClick={vi.fn()} />);
  expect(screen.queryByRole('button', { name: /inspect label/i })).not.toBeInTheDocument();
});

test('zoom button appears when image is present', () => {
  render(
    <WineCard
      density={4}
      wine={makeWine({ image_url: '/wines/test-wine-id/image' })}
      onClick={vi.fn()}
    />,
  );
  expect(screen.getByRole('button', { name: /inspect label/i })).toBeInTheDocument();
});

test('clicking zoom button opens the zoom modal without triggering onClick', async () => {
  const user = userEvent.setup();
  const onClick = vi.fn();
  render(
    <WineCard
      density={4}
      wine={makeWine({ image_url: '/wines/test-wine-id/image' })}
      onClick={onClick}
    />,
  );
  await user.click(screen.getByRole('button', { name: /inspect label/i }));
  expect(screen.getByRole('dialog', { name: /inspect label: château test/i })).toBeInTheDocument();
  expect(onClick).not.toHaveBeenCalled();
});

test('zoom modal shows wine name and vintage in header', async () => {
  const user = userEvent.setup();
  render(
    <WineCard
      density={4}
      wine={makeWine({ image_url: '/wines/test-wine-id/image' })}
      onClick={vi.fn()}
    />,
  );
  await user.click(screen.getByRole('button', { name: /inspect label/i }));
  expect(screen.getByText('Château Test · 2020')).toBeInTheDocument();
});

test('clicking Close button (✕) in zoom modal closes it', async () => {
  const user = userEvent.setup();
  render(
    <WineCard
      density={4}
      wine={makeWine({ image_url: '/wines/test-wine-id/image' })}
      onClick={vi.fn()}
    />,
  );
  await user.click(screen.getByRole('button', { name: /inspect label/i }));
  await user.click(screen.getByRole('button', { name: /close/i }));
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
});

test('clicking backdrop closes the zoom modal', async () => {
  const user = userEvent.setup();
  render(
    <WineCard
      density={4}
      wine={makeWine({ image_url: '/wines/test-wine-id/image' })}
      onClick={vi.fn()}
    />,
  );
  await user.click(screen.getByRole('button', { name: /inspect label/i }));
  const dialog = screen.getByRole('dialog');
  await user.click(dialog);
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
});

test('pressing Escape closes the zoom modal', async () => {
  const user = userEvent.setup();
  render(
    <WineCard
      density={4}
      wine={makeWine({ image_url: '/wines/test-wine-id/image' })}
      onClick={vi.fn()}
    />,
  );
  await user.click(screen.getByRole('button', { name: /inspect label/i }));
  expect(screen.getByRole('dialog')).toBeInTheDocument();
  await user.keyboard('{Escape}');
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
});
