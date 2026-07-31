require "test_helper"

class AttachmentTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @task = tasks(:one)

    # Simulate controller context for PaperTrail (Task/Project are
    # paper-trailed, even though Attachment itself is not).
    setup_paper_trail(ip: "192.168.1.1", user_agent: "TestAgent")
  end

  def teardown
    teardown_paper_trail
  end

  test "valid with a file, task, and user" do
    attachment = Attachment.new(task: @task, user: @user, file: fake_file)
    assert attachment.valid?
  end

  test "invalid without a file" do
    attachment = Attachment.new(task: @task, user: @user)
    assert_not attachment.valid?
    assert_includes attachment.errors[:file], "can't be blank"
  end

  test "invalid without a task" do
    attachment = Attachment.new(user: @user, file: fake_file)
    assert_not attachment.valid?
  end

  test "invalid without a user" do
    attachment = Attachment.new(task: @task, file: fake_file)
    assert_not attachment.valid?
  end

  test "rejects a file over the size cap" do
    oversized = fake_file(content: "x" * (AttachmentUploader::MAX_SIZE + 1))
    attachment = Attachment.new(task: @task, user: @user, file: oversized)
    assert_not attachment.valid?
    assert_includes attachment.errors[:file].join, "too large"
  end

  test "accepts an allowed content type" do
    plain_text = fake_file(content: "hello world", filename: "notes.txt")
    attachment = Attachment.new(task: @task, user: @user, file: plain_text)
    assert attachment.valid?
  end

  test "rejects a disallowed content type" do
    binary_junk = fake_file(content: SecureRandom.random_bytes(100), filename: "mystery.bin")
    attachment = Attachment.new(task: @task, user: @user, file: binary_junk)
    assert_not attachment.valid?
    assert_includes attachment.errors[:file].join, "not allowed"
  end

  test "destroying a task destroys its attachments and their backing blobs" do
    task = Task.create!(title: "Attachment Cascade Task", user: @user, project: @task.project, skip_duplicate_check: true)
    Attachment.create!(task: task, user: @user, file: fake_file)

    assert_difference ["Attachment.count", "AttachmentBlob.count"], -1 do
      task.destroy
    end
  end

  test "creating an attachment bumps the task's project last_activity_at" do
    old_time = 1.day.ago
    @task.project.update_column(:last_activity_at, old_time)

    Attachment.create!(task: @task, user: @user, file: fake_file)

    assert @task.project.reload.last_activity_at > old_time
  end

  test "destroying an attachment bumps the task's project last_activity_at" do
    attachment = Attachment.create!(task: @task, user: @user, file: fake_file)
    old_time = 1.day.ago
    @task.project.update_column(:last_activity_at, old_time)

    attachment.destroy

    assert @task.project.reload.last_activity_at > old_time
  end

  private

  def fake_file(content: "hello world", filename: "test.txt")
    file = StringIO.new(content)
    file.define_singleton_method(:original_filename) { filename }
    file
  end
end
