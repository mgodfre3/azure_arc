@description('The name of the Staging Kubernetes cluster resource')
param aksStagingClusterName string

@description('The location of the Managed Cluster resource')
param location string = resourceGroup().location

@description('Resource tag for Jumpstart Agora')
param resourceTags object = {
  Project: 'Jumpstart_Agora'
}
// Default to 1 node CP
@description('The name of AKS Arc cluster control plane IP, provide this parameter during deployment')
param aksControlPlaneIP string
param aksControlPlaneNodeSize string = 'Standard_A4_v2'
param aksControlPlaneNodeCount int = 1

// Default to 1 node NP
param aksNodePoolName string = 'nodepool1'
param aksNodePoolNodeSize string = 'Standard_A4_v2'
param aksNodePoolNodeCount int = 1
@allowed(['Linux', 'Windows'])
param aksNodePoolOSType string = 'Linux'

@description('SSH public key used for cluster creation, provide this parameter during deployment')
param sshRSAPublicKey string

// Build LNet ID from LNet name
@description('The name of LNet resource, provide this parameter during deployment')
param hciLogicalNetworkName string
resource logicalNetwork 'Microsoft.AzureStackHCI/logicalNetworks@2023-09-01-preview' existing = {
  name: hciLogicalNetworkName
}
// Build custom location ID from custom location name
@description('The name of custom location resource, provide this parameter during deployment')
param hciCustomLocationName string
var customLocationId = resourceId('Microsoft.ExtendedLocation/customLocations', hciCustomLocationName) 

@description('Name of the Azure Container Registry')
param acrName string

@description('Provide a tier of your Azure Container Registry.')
param acrSku string = 'Basic'

// Create the connected cluster. This is the Arc representation of the AKS cluster, used to create a Managed Identity for the provisioned cluster.
resource aksStaging 'Microsoft.Kubernetes/ConnectedClusters@2024-01-01' = {
  location: location
  name: aksStagingClusterName
  tags:resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'ProvisionedCluster'
  properties: {
    agentPublicKeyCertificate: ''
    aadProfile: {
      enableAzureRBAC: false
    }
  }
}

// Create the provisioned cluster instance. This is the actual AKS cluster and provisioned on your HCI cluster via the Arc Resource Bridge.
resource provisionedClusterInstance 'Microsoft.HybridContainerService/provisionedClusterInstances@2024-01-01' = {
  name: 'default'
  scope: aksStaging
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    linuxProfile: {
      ssh: {
        publicKeys: [
          {
            keyData: sshRSAPublicKey
          }
        ]
      }
    }
    controlPlane: {
      count: aksControlPlaneNodeCount
      controlPlaneEndpoint: {
        hostIP: aksControlPlaneIP
      }
      vmSize: aksControlPlaneNodeSize
    }
    networkProfile: {
      loadBalancerProfile: {
        count: 0
      }
      networkPolicy: 'calico'
    }
    agentPoolProfiles: [
      {
        name: aksNodePoolName
        count: aksNodePoolNodeCount
        vmSize: aksNodePoolNodeSize
        osType: aksNodePoolOSType
      }
    ]
    cloudProviderProfile: {
      infraNetworkProfile: {
        vnetSubnetIds: [
          logicalNetwork.id
        ]
      }
    }
    storageProfile: {
      nfsCsiDriver: {
        enabled: true
      }
      smbCsiDriver: {
        enabled: true
      }
    }
  }
}
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' ={
  name: acrName
  location: location
  tags: resourceTags
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: true
  }
}
