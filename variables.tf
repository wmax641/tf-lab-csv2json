variable "base_name" {
  type        = string
  description = "Common displayname to identify objects related to this project"
  default     = "sec-lab-csv2json"
}
variable "protected_file_list" {
  type    = string
  default = "datafile0.csv, datafile1.csv, datafile2.csv, datafile0.md5, datafile1.md5, datafile2.md5"
}
