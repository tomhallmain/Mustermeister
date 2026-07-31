require "shrine"
require "marcel"
require Rails.root.join("lib/shrine/storage/active_record_blob")

# cache and store intentionally point at the same instance - Shrine's model
# integration always promotes cache -> store on save regardless of storage
# backend, so this is fixed lifecycle behavior, not something opted into.
blob_storage = Shrine::Storage::ActiveRecordBlob.new
Shrine.storages = {
  cache: blob_storage,
  store: blob_storage
}

Shrine.plugin :activerecord # model save/destroy lifecycle hooks
Shrine.plugin :validation_helpers # validate_max_size / validate_mime_type

# The built-in `analyzer: :marcel` shorthand does not pass a filename hint
# through to Marcel::MimeType.for in this Shrine version, so pure
# content-sniffing is used - and generic plain text (no distinctive magic
# bytes, unlike images/PDF/zip/office formats) reliably falls back to
# "application/octet-stream" as a result, regardless of the file's actual
# extension. Passing `name:` explicitly lets Marcel use the extension as a
# real signal, which is what correctly resolves e.g. ".txt" to "text/plain".
Shrine.plugin :determine_mime_type, analyzer: -> (io, _analyzers) do
  filename = io.original_filename if io.respond_to?(:original_filename)
  Marcel::MimeType.for(io, name: filename)
end

Shrine.plugin :remove_invalid # deletes the cached blob row on failed validation, no orphans
