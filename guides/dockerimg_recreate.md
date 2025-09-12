# STEPS TO RECREATE YOUR DOCKER.IMG:
> [!IMPORTANT] 
>  Before starting confirm your templates are available on the flash drive at path `/boot/config/plugins/dockerMan/templates-user`, they will show as xml files.
>  If checking the flash drive via windows then it would be just `/config/plugins/dockerMan/templates-user`
> [!IMPORTANT]
> you won't lose any data and all settings for your containers will be retained unless your flash drive is corrupted which is why you check the flash 
drive for the xml templates before starting like mentioned above
  > [!WARNING]
  > this process only works for containers that use templates, so if using compose or run manually then this isn't the guide for you
 
1. make note of the names of any custom networks you created with docker network create
  >  [!NOTE]
  > if you cannot start docker to confirm the names of the custom networks you used and you can't remember them then you can make a userscript with the code shown at the bottom to output the names of any custom networks you have. install the user scripts plugin from the apps page to make the script in
  > if you hadn't created any custom networks you can skip this step
  > [!TIP]
  > optional: go to apps > previous apps and remove anything from your previous installs that you won't want to bring back after to make the next steps go smoother
2. stop docker at settings > docker by setting enable docker to no and hit apply
  > [!TIP]
  > optional: backup the docker.img file using a file manager or via terminal (check path at settings > docker > Docker vDisk location)
  > [!NOTE]
  > optional: change the vdisk size
3. in settings > docker put a check in the delete vdisk file box and hit delete at the bottom
4. in settings > docker change enable docker to yes and hit apply
5. create the custom docker network or networks you had prior by going to unraids terminal and typing the command for each one needing created `docker network create name` changing name to the names you need it to be. If correct you will see a string of characters as output
  > [!NOTE]
  > note: if you hadn't created any custom networks you can skip this step
6. go to apps, then previous apps and select all or select the ones you want and hit install
7. wait for it to finish and you're done now with a fresh docker.img
> [!NOTE]
> BELOW IS THE THE USERSCRIPT DETAILS TO USE IF NEEDED, PUT EVERYTHING STARTING WITH `#!/bin/bash` IN THE SCRIPT AND THE RESULTS WILL DISPLAY IN THE SCRIPTS LOG
> this pulls info from your templates on your flash drive so if you have old templates for things you don't run anymore those custom networks will show as well but it won't hurt anything to create them also
> [!IMPORTANT]
> when making a new script in userscripts plugin it will have the `#!/bin/bash` already, make sure you don't end up with it doubled at the top
 
```bash
#!/bin/bash

# Temporary output file for the results of what custom network names were in use
temporary_output_file="/mnt/user/system/custom_network_list.txt"

# ONLY CHANGE THE OUTPUT LOCATION ABOVE IF NEEDING A DIFFERENT LOCATION. THE FILE IS DELETED AUTOMATICALLY AT THE END OF THE SCRIPT

# DO NOT CHANGE ANYTHING BELOW HERE!!!

# Directory containing XML files
input_dir="/boot/config/plugins/dockerMan/templates-user"

# Check if we can write to the temporary output file location
if ! touch "$temporary_output_file" 2>/dev/null; then
  echo "Error: Unable to write to $temporary_output_file. Check permissions, check if system share exists and what it's settings are."
  exit 1
fi

# Clear the output file
> "$temporary_output_file"

# Loop through all XML files in the directory
for file in "$input_dir"/*.xml; do
  grep -oP '(?<=<Network>).*?(?=</Network>)' "$file" | grep -v "host" | grep -v "none" | grep -v "bridge" | grep -v "^br" | grep -v "^eth" | grep -v "^wg" | grep -v "container:"
done | sort | uniq > "$temporary_output_file"

# Check if the output file is empty
if [[ ! -s "$temporary_output_file" ]]; then
  echo "No custom Docker networks detected."
else
  echo "Custom networks are as follows:"
  while IFS= read -r line; do
    echo "$line"
  done < "$temporary_output_file"
fi

# Removes the temporary output file
rm "$temporary_output_file"
```
