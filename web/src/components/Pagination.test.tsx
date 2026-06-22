import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import Pagination from './Pagination';

test('Previous button is disabled at page 1', () => {
  render(<Pagination page={1} totalPages={5} onPageChange={vi.fn()} />);
  expect(screen.getByRole('button', { name: /previous/i })).toBeDisabled();
});

test('Next button is disabled at the last page', () => {
  render(<Pagination page={5} totalPages={5} onPageChange={vi.fn()} />);
  expect(screen.getByRole('button', { name: /next/i })).toBeDisabled();
});

test('clicking Previous calls onPageChange with page - 1', async () => {
  const user = userEvent.setup();
  const onPageChange = vi.fn();
  render(<Pagination page={3} totalPages={5} onPageChange={onPageChange} />);
  await user.click(screen.getByRole('button', { name: /previous/i }));
  expect(onPageChange).toHaveBeenCalledWith(2);
});

test('clicking Next calls onPageChange with page + 1', async () => {
  const user = userEvent.setup();
  const onPageChange = vi.fn();
  render(<Pagination page={3} totalPages={5} onPageChange={onPageChange} />);
  await user.click(screen.getByRole('button', { name: /next/i }));
  expect(onPageChange).toHaveBeenCalledWith(4);
});

test('displays current page and total pages', () => {
  render(<Pagination page={3} totalPages={7} onPageChange={vi.fn()} />);
  expect(screen.getByText('Page 3 of 7')).toBeInTheDocument();
});
