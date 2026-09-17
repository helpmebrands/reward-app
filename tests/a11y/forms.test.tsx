import { fireEvent, screen, waitFor } from '@solidjs/testing-library'
import { describe, expect, it } from 'vitest'
import { mountRoute } from './mount.tsx'

/**
 * WCAG 3.3.1 and 3.3.3: an error is identified in text, linked to its field,
 * and says what to enter. Add a card is the one form with a submit; the
 * editors validate the same way on blur.
 */
async function reachCardDetails() {
  const mounted = await mountRoute('/cards/new')
  const first = document.querySelector<HTMLButtonElement>('button.catalog')
  if (!first) throw new Error('no catalogue entry')
  first.click()
  const holder = (await screen.findByLabelText(/whose card is it/i)) as HTMLInputElement
  return { ...mounted, holder }
}

describe('inline errors', () => {
  // @lat: [[tests#Accessibility tests#Submitting with a blank holder shows a linked error]]
  it('submitting with a blank holder names the error and focuses the field', async () => {
    const { holder } = await reachCardDetails()
    fireEvent.input(holder, { target: { value: '' } })

    const save = screen.getByRole('button', { name: /add this card/i })
    expect(save).not.toBeDisabled()
    save.click()

    const error = await screen.findByText('Enter whose card this is.')
    expect(holder).toHaveAttribute('aria-invalid', 'true')
    expect(holder.getAttribute('aria-describedby')?.split(' ')).toContain(error.id)
    await waitFor(() => expect(document.activeElement).toBe(holder))
  })

  // @lat: [[tests#Accessibility tests#Correcting the field clears the error and saves]]
  it('correcting the field clears the error and the save goes through', async () => {
    const { app, holder } = await reachCardDetails()
    fireEvent.input(holder, { target: { value: '' } })
    screen.getByRole('button', { name: /add this card/i }).click()
    await screen.findByText('Enter whose card this is.')

    fireEvent.input(holder, { target: { value: 'Kathy' } })
    await waitFor(() =>
      expect(screen.queryByText('Enter whose card this is.')).not.toBeInTheDocument(),
    )
    expect(holder).not.toHaveAttribute('aria-invalid', 'true')

    const before = app.data.cards.length
    screen.getByRole('button', { name: /add this card/i }).click()
    await waitFor(() => expect(app.data.cards.length).toBe(before + 1))
    expect(app.data.cards.at(-1)?.holder).toBe('Kathy')
  })
})
