# frozen_string_literal: true

class AttachmentUploader < Shrine
  # 5MB, not a larger local-disk-style cap - Postgres rows/blobs are more
  # expensive than disk for storage/backup/query overhead, so DB-backed
  # storage comes with a tighter size ceiling.
  MAX_SIZE = 5.megabytes

  ALLOWED_TYPES = %w[
    image/png image/jpeg image/gif image/webp
    application/pdf
    text/plain
    text/markdown
    text/csv
    application/msword
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.ms-excel
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.ms-powerpoint
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/vnd.oasis.opendocument.text
    application/vnd.oasis.opendocument.spreadsheet
    application/vnd.oasis.opendocument.presentation
    application/zip
  ].freeze
  # Note: marcel (Shrine's determine_mime_type analyzer) has no distinct
  # magic-byte signature for Markdown, so .md files are typically sniffed as
  # text/plain rather than text/markdown - both are allowlisted, so this
  # doesn't affect whether .md uploads are accepted.

  Attacher.validate do
    validate_max_size AttachmentUploader::MAX_SIZE,
      message: I18n.t("activerecord.errors.models.attachment.attributes.file.file_too_large", max: AttachmentUploader::MAX_SIZE / 1.megabyte)
    validate_mime_type AttachmentUploader::ALLOWED_TYPES,
      message: I18n.t("activerecord.errors.models.attachment.attributes.file.invalid_content_type")
  end
end
