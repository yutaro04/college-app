import { BIO_MAX, DISPLAY_NAME_MAX, type ResidentProfile, type ResidentRepository } from '../domain/resident'
import { UseCaseError } from './errors'

export async function updateMyProfile(
  repo: ResidentRepository,
  residentId: string,
  body: { displayName?: unknown; bio?: unknown }
): Promise<ResidentProfile> {
  const patch: { displayName?: string; bio?: string | null } = {}
  if (body.displayName !== undefined) {
    const name = typeof body.displayName === 'string' ? body.displayName.trim() : ''
    if (!name) throw new UseCaseError(400, '表示名を入力してください')
    if (name.length > DISPLAY_NAME_MAX) throw new UseCaseError(400, `表示名は${DISPLAY_NAME_MAX}文字以内にしてください`)
    patch.displayName = name
  }
  if (body.bio !== undefined) {
    const bio = typeof body.bio === 'string' ? body.bio.trim() : ''
    if (bio.length > BIO_MAX) throw new UseCaseError(400, `自己紹介は${BIO_MAX}文字以内にしてください`)
    patch.bio = bio || null
  }
  await repo.updateProfile(residentId, patch)
  const resident = await repo.findProfile(residentId)
  if (!resident) throw new UseCaseError(404, 'not_found')
  return resident
}
