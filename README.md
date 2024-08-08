# Debian Dreamweaver

Debian Dreamweaver is a script to install and configure a fresh Debian installation with my daily use desktop.

## Usage

1. Clone the repository:

   ```bash
   git clone https://github.com/h3nc4/Debian-Dreamweaver.git
   cd Debian-Dreamweaver
    ```

2. Run the script:

   ```bash
   ./run
   ```

3. Follow the instructions on screen.

## Main Contents

- [`run`](run): The main script to run. Includes all steps to install and configure your system.
- [`config/bashrc`](config/bashrc): My personal `.bashrc` file.
- [`config/profile.d/`](config/profile.d/): Directory with scripts to be sourced by the user profile.
- [`utils/`](utils/): Directory with useful scripts to install and configure many applications and tools.

## Usage Notes

For optimal security, it is recommended to use this script on an encrypted system, as it includes enabling auto-login and passwordless sudo privileges.

## Logs

In case of any errors, check the `logs` directory.

## License

Debian Dreamweaver is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

Debian Dreamweaver is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

See [LICENSE](LICENSE) for more information.
