{
  description = "lua-pam: Lua PAM authentication module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = {
          default = self.packages.${system}.lua-pam;

          lua-pam = pkgs.stdenv.mkDerivation rec {
            pname = "lua-pam";
            version = "0.1.0";

            src = ./.;

            nativeBuildInputs = with pkgs; [
              cmake
              pkg-config
            ];

            buildInputs = with pkgs; [
              luajit
              pam
            ];

            # Configure CMake to find LuaJIT headers and libraries
            cmakeFlags = [
              "-DCMAKE_BUILD_TYPE=Release"
              "-DCMAKE_CXX_STANDARD=14"
              "-DLUA_INCLUDE_DIR=${pkgs.luajit}/include/luajit-2.1"
              "-DLUA_LIBRARY=${pkgs.luajit}/lib/libluajit-5.1.so"
            ];

            # Override CMake's lua detection to use LuaJIT specifically
            preConfigure = ''
              export PKG_CONFIG_PATH="${pkgs.luajit}/lib/pkgconfig:$PKG_CONFIG_PATH"
              export CMAKE_PREFIX_PATH="${pkgs.luajit}:$CMAKE_PREFIX_PATH"
            '';

            # Replace CMake references to lua with luajit
            postPatch = ''
              # Replace lua with luajit-5.1 in CMakeLists.txt
              sed -i 's/target_link_libraries(lua_pam lua pam)/target_link_libraries(lua_pam luajit-5.1 pam)/' CMakeLists.txt
              
              # Add LuaJIT include directory
              sed -i '/add_library(lua_pam SHARED/a target_include_directories(lua_pam PRIVATE ${pkgs.luajit}/include/luajit-2.1)' CMakeLists.txt
            '';

            # Install the shared library to the appropriate location
            installPhase = ''
              runHook preInstall
              
              mkdir -p $out/lib/lua/5.1
              cp liblua_pam.so $out/lib/lua/5.1/
              
              # Also install to a more standard location
              mkdir -p $out/lib
              cp liblua_pam.so $out/lib/
              
              runHook postInstall
            '';

            # Add metadata
            meta = with pkgs.lib; {
              description = "PAM authentication module for Lua/LuaJIT";
              homepage = "https://github.com/user/lua-pam"; # Update with actual URL if available
              license = licenses.mit; # Update with actual license
              maintainers = [ ];
              platforms = platforms.linux; # PAM is primarily Linux/Unix
            };
          };

          # Alternative package that uses standard Lua instead of LuaJIT
          lua-pam-lua = pkgs.stdenv.mkDerivation rec {
            pname = "lua-pam-lua";
            version = "0.1.0";

            src = ./.;

            nativeBuildInputs = with pkgs; [
              cmake
              pkg-config
            ];

            buildInputs = with pkgs; [
              lua
              pam
            ];

            cmakeFlags = [
              "-DCMAKE_BUILD_TYPE=Release"
              "-DCMAKE_CXX_STANDARD=14"
            ];

            installPhase = ''
              runHook preInstall
              
              mkdir -p $out/lib/lua/5.4
              cp liblua_pam.so $out/lib/lua/5.4/
              
              mkdir -p $out/lib
              cp liblua_pam.so $out/lib/
              
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "PAM authentication module for standard Lua";
              homepage = "https://github.com/user/lua-pam";
              license = licenses.mit;
              maintainers = [ ];
              platforms = platforms.linux;
            };
          };
        };

        # Development environment
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Build tools
            cmake
            pkg-config
            gcc
            
            # Runtime dependencies
            luajit
            pam
            
            # Development tools
            gdb
            valgrind
            
            # Lua development
            lua-language-server
          ];

          shellHook = ''
            echo "lua-pam development environment"
            echo "LuaJIT version: $(luajit -v)"
            echo "CMake version: $(cmake --version | head -n1)"
            echo ""
            echo "To build:"
            echo "  cmake . -B build"
            echo "  cd build && make"
            echo ""
            echo "To test with LuaJIT:"
            echo "  luajit -e \"package.cpath = package.cpath .. ';./build/liblua_pam.so'\""
            echo "  luajit -e \"local pam = require('liblua_pam'); print('PAM module loaded')\""
          '';
          
          # Environment variables for development
          CMAKE_PREFIX_PATH = "${pkgs.luajit}";
          PKG_CONFIG_PATH = "${pkgs.luajit}/lib/pkgconfig";
        };

        # Development shell with standard Lua
        devShells.lua = pkgs.mkShell {
          buildInputs = with pkgs; [
            cmake
            pkg-config
            gcc
            lua
            pam
            gdb
            valgrind
            lua-language-server
          ];

          shellHook = ''
            echo "lua-pam development environment (standard Lua)"
            echo "Lua version: $(lua -v)"
            echo "CMake version: $(cmake --version | head -n1)"
          '';
        };

        # CI/Testing apps
        apps = {
          build = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "build-lua-pam" ''
              set -e
              echo "Building lua-pam with LuaJIT..."
              nix build .#lua-pam
              echo "Build completed successfully!"
              echo "Output: $(readlink -f result)"
            '';
          };

          test = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "test-lua-pam" ''
              set -e
              echo "Testing lua-pam module..."
              nix build .#lua-pam
              
              # Basic load test
              ${pkgs.luajit}/bin/luajit -e "
                package.cpath = package.cpath .. ';./result/lib/?.so'
                local success, pam = pcall(require, 'liblua_pam')
                if success then
                  print('✓ PAM module loaded successfully')
                else
                  print('✗ Failed to load PAM module: ' .. tostring(pam))
                  os.exit(1)
                end
              "
            '';
          };
        };
      }
    );
}