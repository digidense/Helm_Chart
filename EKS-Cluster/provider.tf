terraform {
  required_providers {
    aws = {
      source  = "lxpcppsgv001.sg.uobnet.com/uob/aws"
      version = ">=5.66.0"
    }
    time = {
      source  = "lxpcppsgv001.sg.uobnet.com/uob/time"
      version = "0.9.1"
    }
    archive = {
      source  = "lxpcppsgv001.sg.uobnet.com/uob/archive"
      version = "2.4.0"
    }
    tls = {
      source  = "lxpcppsgv001.sg.uobnet.com/uob/tls"
      version = "4.1.0"
    }
  }
}