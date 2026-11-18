// ユースケースが返す「利用者に見せてよい」エラー。presentation 層で { error } と HTTP ステータスに変換する
export class UseCaseError extends Error {
  constructor(
    readonly status: 400 | 401 | 403 | 404 | 409 | 500 | 502,
    message: string
  ) {
    super(message)
  }
}
