{ pkgs, ... }: {
  channel = "stable-24.05";
  
  # Full list of packages for a glitch-free experience
  packages = with pkgs; [ 
    unzip 
    openssh 
    git 
    qemu_kvm 
    sudo 
    cdrkit 
    cloud-utils 
    qemu
    apt          
    dpkg         
    bashInteractive
    coreutils
    glibcLocales 
  ];

  env = { 
    EDITOR = "nano";
    LANG = "en_US.UTF-8"; # Ensures text displays correctly
  };

  idx = {
    extensions = [ 
      "Dart-Code.flutter" 
      "Dart-Code.dart-code" 
    ];
    
    workspace = { 
      onCreate = {
        # Commands to run the very first time
      }; 
      onStart = {
        # Commands to run every time the workspace opens
      }; 
    };

    previews = { 
      enable = false; 
    };
  };
}
