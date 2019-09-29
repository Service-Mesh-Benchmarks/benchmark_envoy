variable "do_token" {
	description = "Your DigitalOcean API token. Get this from the DigitalOcean website."
}

variable "user_ssh_key_name" {
	description = "Registered name of the SSH key attached to your Digitalocean account."
}

provider "digitalocean" {
	token = "${var.do_token}"
}

data "digitalocean_ssh_key" "user" {
        name = "${var.user_ssh_key_name}"
}

resource "digitalocean_droplet" "benchmark_machine" {
	# this image is built in the /image folder
	image  = "benchmark_image"
	name   = "benchmark-instance-1"
	region = "blr1"
	size   = "s-4vcpu-8gb"
        ssh_keys = ["${data.digitalocean_ssh_key.user.id}"]
}
