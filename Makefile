fmtchk:
	terraform fmt -write=false -diff=true -check=true

fmtfix:
	terraform fmt -write=true

validate:
	terraform validate

plan: 
	terraform plan -input=false -out=tfplan-pit

apply:
	terraform apply -input=false tfplan-pit

destroy:
	terraform plan -destroy -input=false -out=tfplan-pit
	terraform apply -input=false tfplan-pit
