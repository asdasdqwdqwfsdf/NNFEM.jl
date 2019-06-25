export SmallStrainContinuum
mutable struct SmallStrainContinuum
    mat  # constitutive law
    elnodes::Array{Int64}   # the node indices in this finite element
    props::Dict{String, Any}
    coords::Array{Float64}
    dhdx::Array{Array{Float64}}  # 4nPointsx2 matrix
    weights::Array{Float64} 
    hs::Array{Array{Float64}}
end

function SmallStrainContinuum(coords::Array{Float64}, elnodes::Array{Int64}, props::Dict{String, Any})
    name = props["name"]
    if name=="PlaneStrain"
        mat = PlaneStrain(props)
    elseif name=="Plasticity"
        mat = Plasticity(props)
    else
        error("Not implemented yet: $name")
    end
    dhdx, weights, hs = getElemShapeData( coords, 2 )
    SmallStrainContinuum(mat, elnodes, props, coords, dhdx, weights, hs)
end

function getStiffAndForce(self::SmallStrainContinuum, state::Array{Float64}, Dstate::Array{Float64})
    ndofs = dofCount(self); 
    nnodes = length(self.elnodes)
    fint = zeros(Float64, ndofs)
    stiff = zeros(Float64, ndofs,ndofs)
    out = Array{Float64}[]
    u = state[1:nnodes]; v = state[nnodes+1:2*nnodes]
    Du = Dstate[1:nnodes]; Dv = Dstate[nnodes+1:2*nnodes]
    for k = 1:length(self.weights)
        g1 = self.dhdx[k][:,1]; g2 = self.dhdx[k][:,2]
        
        ux = u'*g1; uy = u'*g2; vx = v'*g1; vy = v'*g2
        Dux = Du'*g1; Duy = Du'*g2; Dvx = Dv'*g1; Dvy = Dv'*g2
        # compute  ∂E∂u.T, 8 by 3 array 
        ∂E∂u = [g1   zeros(nnodes)    g2;
                zeros(nnodes)    g2   g1;] 
        
        E = [ux; vy; uy+vx]
        DE = [Dux; Dvy; Duy+Dvx]

        S, dS_dE = getStress(self.mat, E, DE)

        fint += ∂E∂u * S * self.weights[k] # 1x8
        
        stiff += (∂E∂u * dS_dE * ∂E∂u')*self.weights[k] # 8x8
    end
    return fint, stiff
end

function getInternalForce(self::SmallStrainContinuum, state::Array{Float64}, Dstate::Array{Float64})
    n = dofCount(self)
    fint = zeros(Float64,n)
    out = Array{Float64}[]
    u = state[1:4]; v = state[5:8]
    Du = Dstate[1:4]; Dv = Dstate[5:8]
    for k = 1:length(self.weights)
        g1 = self.dhdx[k][:,1]; g2 = self.dhdx[k][:,2]
        
        ux = u'*g1; uy = u'*g2; vx = v'*g1; vy = v'*g2
        Dux = Du'*g1; Duy = Du'*g2; Dvx = Dv'*g1; Dvy = Dv'*g2
        # compute  ∂E∂u.T, 8 by 3 array 
        ∂E∂u = [g1   zeros(4)    g2;
                zeros(4)    g2   g1;] 
        
        E = [ux; vy; uy+vx]
        DE = [Dux; Dvy; Duy+Dvx]

        S, dS_dE = getStress(self.mat, E, DE)

        fint += ∂E∂u * S * self.weights[k] # 1x8
    end
    return fint
end

function getMassMatrix(self::SmallStrainContinuum)
    ndofs = dofCount(self)
    nnodes = length(self.elnodes)
    rho = self.mat.ρ
    mass = zeros(ndofs,ndofs)
    for k = 1:length(self.weights)
        mass += [self.hs[k]*self.hs[k]' zeros(nnodes, nnodes)
                 zeros(nnodes, nnodes)  self.hs[k]*self.hs[k]']  * rho * self.weights[k]
    end
    lumped = sum(mass, dims=2)
    mass, lumped
end


function getNodes(self::SmallStrainContinuum)
    return self.elnodes
end

function dofCount(self::SmallStrainContinuum)
    return 2length(self.elnodes)
end