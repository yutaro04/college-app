export type ResidentPhotoKind = 'face' | 'paper_directory' | 'gallery'

export interface ResidentPhoto {
  id: string
  residentId: string
  kind: ResidentPhotoKind
  r2Key: string
  caption: string | null
  sortOrder: number
  createdAt: string
}

export interface Event {
  id: string
  title: string
  eventDate: string
  createdByResidentId: string | null
  createdAt: string
}

export interface EventVideoClip {
  id: string
  eventId: string
  residentId: string
  r2Key: string
  durationMs: number | null
  createdAt: string
}

export type MemoryVideoStatus = 'pending' | 'processing' | 'completed' | 'failed'

export interface EventMemoryVideo {
  id: string
  eventId: string
  requestedByResidentId: string
  musicR2Key: string
  status: MemoryVideoStatus
  outputR2Key: string | null
  errorMessage: string | null
  createdAt: string
  completedAt: string | null
}
