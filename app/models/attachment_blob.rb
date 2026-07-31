# frozen_string_literal: true

# Internal storage backend for Shrine::Storage::ActiveRecordBlob - not a
# domain model, and shouldn't be referenced outside that storage class.
class AttachmentBlob < ApplicationRecord
end
