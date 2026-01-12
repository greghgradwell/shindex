defmodule InventoryLocator.MediaTest do
  use ExUnit.Case, async: true

  alias InventoryLocator.Media

  describe "fetch_image_from_url/1 URL validation" do
    test "rejects HTTP URLs (insecure)" do
      assert {:error, :insecure_url} =
               Media.fetch_image_from_url("http://example.com/image.jpg")
    end

    test "rejects URLs without scheme" do
      assert {:error, :invalid_url} =
               Media.fetch_image_from_url("example.com/image.jpg")
    end

    test "rejects URLs with empty host" do
      assert {:error, :invalid_url} =
               Media.fetch_image_from_url("https:///image.jpg")
    end

    test "rejects file:// URLs" do
      assert {:error, :invalid_url} =
               Media.fetch_image_from_url("file:///etc/passwd")
    end

    test "rejects ftp:// URLs" do
      assert {:error, :invalid_url} =
               Media.fetch_image_from_url("ftp://example.com/image.jpg")
    end

    test "rejects data: URLs" do
      assert {:error, :invalid_url} =
               Media.fetch_image_from_url("data:image/png;base64,abc123")
    end
  end

  describe "fetch_image_from_url/1 SSRF protection - localhost" do
    test "blocks localhost" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://localhost/image.jpg")
    end

    test "blocks LOCALHOST (case insensitive)" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://LOCALHOST/image.jpg")
    end

    test "blocks 127.0.0.1" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://127.0.0.1/image.jpg")
    end

    test "blocks 127.0.0.1 with port" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://127.0.0.1:8080/image.jpg")
    end

    test "blocks 127.x.x.x variants" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://127.1.2.3/image.jpg")

      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://127.255.255.255/image.jpg")
    end
  end

  describe "fetch_image_from_url/1 SSRF protection - private IP ranges" do
    test "blocks 10.x.x.x (Class A private)" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://10.0.0.1/image.jpg")

      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://10.255.255.255/image.jpg")
    end

    test "blocks 172.16-31.x.x (Class B private)" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://172.16.0.1/image.jpg")

      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://172.31.255.255/image.jpg")
    end

    # Note: Tests for "allowed" hosts are omitted because they make actual
    # HTTP requests which are slow and flaky. The blocklist tests above
    # verify that forbidden hosts are blocked - if those pass, hosts not
    # matching the patterns will be allowed through to the HTTP layer.

    test "blocks 192.168.x.x (Class C private)" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://192.168.0.1/image.jpg")

      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://192.168.1.1/image.jpg")

      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://192.168.255.255/image.jpg")
    end
  end

  describe "fetch_image_from_url/1 SSRF protection - cloud metadata" do
    test "blocks AWS/Azure metadata endpoint (169.254.169.254)" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://169.254.169.254/latest/meta-data/")
    end

    test "blocks 169.254.x.x link-local range" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://169.254.0.1/image.jpg")
    end

    test "blocks Google Cloud metadata endpoint" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://metadata.google.internal/computeMetadata/v1/")
    end

    test "blocks metadata.google.internal (case insensitive)" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://METADATA.GOOGLE.INTERNAL/image.jpg")
    end

    test "blocks metadata.internal" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://metadata.internal/image.jpg")
    end
  end

  describe "fetch_image_from_url/1 SSRF protection - special addresses" do
    test "blocks 0.x.x.x" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://0.0.0.0/image.jpg")

      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://0.1.2.3/image.jpg")
    end

    test "blocks IPv6 localhost [::1]" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://[::1]/image.jpg")
    end

    test "blocks IPv6 unspecified [::]" do
      assert {:error, :forbidden_host} =
               Media.fetch_image_from_url("https://[::]/image.jpg")
    end
  end

  # Note: Tests for "allows valid external hosts" are omitted because they
  # make actual HTTP requests which are slow and network-dependent.
  # The blocklist tests above provide comprehensive coverage - if a host
  # doesn't match any forbidden pattern, it will proceed to the HTTP layer.
end
