# frozen_string_literal: true

# Minimal Shrine storage backed by the attachment_blobs table (see
# AttachmentBlob), rather than local disk or S3 - keeps attachment bytes in
# this app's own Postgres database, avoiding a persistent volume mount for
# the Kamal-deployed, ephemeral-container production environment.
class Shrine
  module Storage
    class ActiveRecordBlob
      def upload(io, id, shrine_metadata: {}, **)
        AttachmentBlob.create!(blob_id: id, data: io.read)
      end

      def open(id, **)
        StringIO.new(AttachmentBlob.find_by!(blob_id: id).data)
      end

      def exists?(id)
        AttachmentBlob.exists?(blob_id: id)
      end

      def delete(id)
        AttachmentBlob.where(blob_id: id).delete_all
      end

      def url(id, **)
        nil # downloads are always served via AttachmentsController#download, never a direct storage URL
      end

      def clear!
        AttachmentBlob.delete_all # test-only convenience, mirrors Shrine::Storage::Memory#clear!
      end
    end
  end
end
