variable "base_name" {
  type    = string
  default = "lab-csv2json"
}
variable "protected_file_list" {
  type    = string
  default = "datafile0.csv, datafile1.csv, datafile2.csv, datafile0.csv.md5, datafile1.csv.md5, datafile2.csv.md5"
}
variable "common_tags" {
  default = {
    "Project" = "tf-lab-csv2json"
  }
}
