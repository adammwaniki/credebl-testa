
resource "aws_secretsmanager_secret" "nkey_secrets" {
  for_each = toset(local.services)

  name = "${each.key}_NKEY"
}


resource "aws_secretsmanager_secret" "seed_secrets" {
  for_each = toset(local.services)

  name = "${each.key}_NKEY_SEED"
}


resource "null_resource" "generate_nkeys" {
  provisioner "local-exec" {
    command = <<EOT
      cd ${path.module}/nkeys/nk
      # Ensure files are created in the root directory
      echo "" > ../../SEED_FILE
      echo "" > ../../PUB_FILE
      echo "" > ../../SEED_FILE_TEMP

      for service in ${join(" ", local.services)}; do
        # Generate the seed key and append to SEED_FILE_TEMP
        SEED_KEY=$(go run main.go -gen user)
        echo "$SEED_KEY" >> ../../SEED_FILE_TEMP
        

         # Write secrets to Secrets Manager
      aws --profile ${var.profile} --region ${var.region} secretsmanager put-secret-value \
        --secret-id "$${service}_NKEY_SEED" \
        --secret-string "{\"$${service}_NKEY_SEED\":\"$SEED_KEY\"}"



       

        # Optionally, append the seed key to SEED_FILE (uncomment if you need this)
        echo "$service=$SEED_KEY" >> ../../SEED_FILE

        # Generate the public key and append to PUB_FILE
        PUB_KEY=$(go run main.go -inkey ../../SEED_FILE_TEMP -pubout)
        
        
         # Write secrets to Secrets Manager
      aws --profile ${var.profile} --region ${var.region} secretsmanager put-secret-value \
        --secret-id "$${service}_NKEY" \
        --secret-string "{\"$${service}_NKEY\":\"$PUB_KEY\"}"
        
       

        # Optionally, append the public key to PUB_FILE (uncomment if you need this)
        echo "$service=$PUB_KEY" >> ../../PUB_FILE
        
        # Clear the temporary seed file for the next iteration
        truncate -s 0 ../../SEED_FILE_TEMP
      done
      
      # Clean up the temporary seed file
      rm -rf ../../SEED_FILE_TEMP
    EOT
  }
  depends_on = [ aws_secretsmanager_secret.nkey_secrets,aws_secretsmanager_secret.seed_secrets ]
}


# resource "null_resource" "generate_nkeys" {
#   provisioner "local-exec" {
#     command = <<EOT
#       cd ${path.module}/nkeys/nk
#       # Ensure files are created in the root directory
#       echo "" > ../../SEED_FILE
#       echo "" > ../../PUB_FILE
#       echo "" > ../../SEED_FILE_TEMP

#       for service in ${join(" ", local.services)}; do
#         # Generate the seed key and append to SEED_FILE_TEMP
#         SEED_KEY=$(go run main.go -gen user)
#         echo "$SEED_KEY" >> ../../SEED_FILE_TEMP

#         # Create or update the secret in Secrets Manager for each service
#         aws secretsmanager create-secret --name "$${service}_SEED_KEY" \
#           --secret-string "{\"$${service}_SEED_KEY\":\"$SEED_KEY\"}" || \
#           aws secretsmanager update-secret --secret-id "$${service}_SEED_KEY" \
#           --secret-string "{\"$${service}_SEED_KEY\":\"$SEED_KEY\"}"

#         # Optionally, append the seed key to SEED_FILE (uncomment if you need this)
#         echo "$service=$SEED_KEY" >> ../../SEED_FILE

#         # Generate the public key and append to PUB_FILE
#         PUB_KEY=$(go run main.go -inkey ../../SEED_FILE_TEMP -pubout)
#         # Create or update the secret in Secrets Manager for each service
#         aws secretsmanager create-secret --name "$${service}_NKEY" \
#           --secret-string "{\"$${service}_NKEY\":\"$PUB_KEY\"}" || \
#           aws secretsmanager update-secret --secret-id "$${service}_NKEY" \
#           --secret-string "{\"$${service}_NKEY\":\"$PUB_KEY\"}"

#         # Optionally, append the public key to PUB_FILE (uncomment if you need this)
#         echo "$service=$PUB_KEY" >> ../../PUB_FILE
        
#         # Clear the temporary seed file for the next iteration
#         truncate -s 0 ../../SEED_FILE_TEMP
#       done
      
#       # Clean up the temporary seed file
#       rm -rf ../../SEED_FILE_TEMP
#     EOT
#   }
# }
