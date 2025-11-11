{...}: {
  services.tikv = {
    tikv1 = {
      enable = true;
      addr = "127.0.0.1:20160";
      statusAddr = "127.0.0.1:20180";
      dataDir = "/var/lib/tikv/tikv1";
      logLevel = "info";
      config = {
        wait-for-lock-timeout = "2s";
      };
    };

    tikv2 = {
      enable = true;
      addr = "127.0.0.1:20161";
      statusAddr = "127.0.0.1:20181";
      dataDir = "/var/lib/tikv/tikv2";
      logLevel = "info";
    };

    tikv3 = {
      enable = true;
      addr = "127.0.0.1:20162";
      statusAddr = "127.0.0.1:20182";
      dataDir = "/var/lib/tikv/tikv3";
      logLevel = "info";
    };
  };

  # For nixos-shell compatibility
  users.users.root.initialPassword = "test";
  services.getty.autologinUser = "root";
}
