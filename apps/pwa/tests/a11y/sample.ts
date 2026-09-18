import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import type { AppData } from '../../src/domain/types.ts'

/**
 * The sample household, read at run time rather than imported as a module:
 * `samples/` is outside the Docker build context, and the image's typecheck
 * covers `tests/`, so a JSON import would fail the container build.
 *
 * Resolved from the working directory because both runners start at the
 * repository root, and `import.meta.url` is not a file URL under Vitest.
 */
export function loadSampleHousehold(): AppData {
  const path = resolve(process.cwd(), 'samples', 'sample-household.json')
  return JSON.parse(readFileSync(path, 'utf8')) as AppData
}
