require "test_helper"

class AttachmentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @task = tasks(:one)
    sign_in_as(@user, skip_redirect: true)
    setup_paper_trail
  end

  def teardown
    teardown_paper_trail
  end

  test "create as task owner with a valid file redirects with a notice and persists the attachment" do
    assert_difference "Attachment.count", 1 do
      post task_attachments_path(@task), params: { attachment: { file: sample_upload } }
    end

    assert_redirected_to task_path(@task)
    assert_equal I18n.t("views.attachments.created"), flash[:notice]
  end

  test "create with no file redirects with an alert and does not persist" do
    assert_no_difference "Attachment.count" do
      post task_attachments_path(@task), params: { attachment: {} }
    end

    assert_redirected_to task_path(@task)
    assert flash[:alert].present?
  end

  test "create with an oversized file redirects with an alert and does not persist" do
    oversized = fixture_file_upload("sample_attachment.txt", "text/plain")
    oversized.tempfile.write("x" * (AttachmentUploader::MAX_SIZE + 1))
    oversized.tempfile.rewind

    assert_no_difference "Attachment.count" do
      post task_attachments_path(@task), params: { attachment: { file: oversized } }
    end

    assert_redirected_to task_path(@task)
    assert flash[:alert].present?
  end

  test "create with a disallowed content type redirects with an alert and does not persist" do
    # Uses a real fixture file with a disallowed extension (.exe), rather
    # than swapping bytes into the .txt fixture - marcel falls back to the
    # filename extension as a hint for content that has no distinctive
    # magic-byte signature of its own, so a mismatched-but-still-.txt-named
    # upload no longer reliably exercises rejection once that hint is honored.
    disallowed = fixture_file_upload("malicious.exe", "application/octet-stream")

    assert_no_difference "Attachment.count" do
      post task_attachments_path(@task), params: { attachment: { file: disallowed } }
    end

    assert_redirected_to task_path(@task)
    assert flash[:alert].present?
  end

  test "create against another user's task 404s" do
    other_task = projects(:two).tasks.create!(title: "Someone else's task", user: users(:two))

    silence_expected_error_logging do
      post task_attachments_path(other_task), params: { attachment: { file: sample_upload } }
    end

    assert_response :not_found
  end

  test "create against an archived task 404s" do
    @task.archive!(@user)

    silence_expected_error_logging do
      post task_attachments_path(@task), params: { attachment: { file: sample_upload } }
    end

    assert_response :not_found
  end

  test "destroy as task owner redirects with a notice and removes the attachment and its blob" do
    attachment = Attachment.create!(task: @task, user: @user, file: sample_upload)

    assert_difference ["Attachment.count", "AttachmentBlob.count"], -1 do
      delete attachment_path(attachment)
    end

    assert_redirected_to task_path(@task)
    assert_equal I18n.t("views.attachments.deleted"), flash[:notice]
  end

  test "destroy on another user's attachment 404s" do
    other_task = projects(:two).tasks.create!(title: "Someone else's task", user: users(:two))
    other_attachment = Attachment.create!(task: other_task, user: users(:two), file: sample_upload)

    assert_no_difference "Attachment.count" do
      silence_expected_error_logging do
        delete attachment_path(other_attachment)
      end
    end

    assert_response :not_found
  end

  test "download as task owner returns the file with a forced download disposition" do
    attachment = Attachment.create!(task: @task, user: @user, file: sample_upload)

    get download_attachment_path(attachment)

    assert_response :success
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/sample_attachment\.txt/, response.headers["Content-Disposition"])
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal File.read(file_fixture("sample_attachment.txt")), response.body
  end

  test "download on another user's attachment 404s" do
    other_task = projects(:two).tasks.create!(title: "Someone else's task", user: users(:two))
    other_attachment = Attachment.create!(task: other_task, user: users(:two), file: sample_upload)

    silence_expected_error_logging do
      get download_attachment_path(other_attachment)
    end

    assert_response :not_found
  end

  test "uploading an attachment bumps the task's project last_activity_at" do
    old_time = 1.day.ago
    @task.project.update_column(:last_activity_at, old_time)

    post task_attachments_path(@task), params: { attachment: { file: sample_upload } }

    assert @task.project.reload.last_activity_at > old_time
  end

  test "deleting an attachment bumps the task's project last_activity_at" do
    attachment = Attachment.create!(task: @task, user: @user, file: sample_upload)
    old_time = 1.day.ago
    @task.project.update_column(:last_activity_at, old_time)

    delete attachment_path(attachment)

    assert @task.project.reload.last_activity_at > old_time
  end

  private

  def sample_upload
    fixture_file_upload("sample_attachment.txt", "text/plain")
  end
end
