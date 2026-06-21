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
  render(<WineCard wine={makeWine()} onClick={vi.fn()} />);
  expect(screen.getByText('Château Test')).toBeInTheDocument();
  expect(screen.getByText('2020')).toBeInTheDocument();
  expect(screen.queryByRole('img')).not.toBeInTheDocument();
});

test('renders image when image_url is set', () => {
  render(
    <WineCard wine={makeWine({ image_url: '/wines/test-wine-id/image' })} onClick={vi.fn()} />,
  );
  const img = screen.getByRole('img', { name: 'Château Test' });
  expect(img).toHaveAttribute('src', '/wines/test-wine-id/image');
});

test('shows verified badge when wine is verified', () => {
  render(<WineCard wine={makeWine({ verified: true })} onClick={vi.fn()} />);
  expect(screen.getByText('✓')).toBeInTheDocument();
});

test('does not show verified badge when wine is unverified', () => {
  render(<WineCard wine={makeWine({ verified: false })} onClick={vi.fn()} />);
  expect(screen.queryByText('✓')).not.toBeInTheDocument();
});

test('calls onClick when card is clicked', async () => {
  const user = userEvent.setup();
  const onClick = vi.fn();
  render(<WineCard wine={makeWine()} onClick={onClick} />);
  await user.click(screen.getByRole('button'));
  expect(onClick).toHaveBeenCalled();
});
