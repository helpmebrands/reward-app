import { fireEvent, screen, waitFor, within } from '@solidjs/testing-library'
import { describe, expect, it } from 'vitest'
import { mountRoute } from './mount.tsx'

/**
 * Undo without a timer: the credit sheet lists what has been logged this
 * period, each with a Remove, so a claim can be taken back at any time and
 * not only in the seconds after logging it.
 */
describe('claims in the credit sheet', () => {
  // @lat: [[tests#Accessibility tests#The sheet lists claims with a Remove]]
  it('lists a logged claim and Remove restores the balance', async () => {
    const { app, ui } = await mountRoute('/')
    const open = app.instances().find((i) => i.status === 'available' || i.status === 'use_soon')
    if (!open) throw new Error('no open credit in the sample')
    const before = open.remainingCents
    const id = open.benefit.id

    ui.openCredit(id)
    const sheet = await screen.findByRole('dialog')
    fireEvent.click(within(sheet).getByRole('button', { name: /mark the full/i }))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(app.instances().find((i) => i.benefit.id === id)?.remainingCents).toBe(0)

    ui.openCredit(id)
    const reopened = await screen.findByRole('dialog')
    const remove = await within(reopened).findByRole('button', { name: /^remove/i })
    fireEvent.click(remove)

    await waitFor(() =>
      expect(app.instances().find((i) => i.benefit.id === id)?.remainingCents).toBe(before),
    )
    expect(within(reopened).queryByRole('button', { name: /^remove/i })).not.toBeInTheDocument()
  })
})
