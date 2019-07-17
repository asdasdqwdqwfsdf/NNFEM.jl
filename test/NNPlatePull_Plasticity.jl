using Revise
using Test 
using NNFEM
using PyCall
using PyPlot
using JLD2
using ADCME
using LinearAlgebra


# testtype = "PlaneStressPlasticity"
testtype = "NeuralNetwork2D"
np = pyimport("numpy")
nx, ny =  1,2
nnodes, neles = (nx + 1)*(ny + 1), nx*ny
x = np.linspace(0.0, 0.5, nx + 1)
y = np.linspace(0.0, 0.5, ny + 1)
X, Y = np.meshgrid(x, y)
nodes = zeros(nnodes,2)
nodes[:,1], nodes[:,2] = X'[:], Y'[:]
ndofs = 2

EBC, g = zeros(Int64, nnodes, ndofs), zeros(nnodes, ndofs)

EBC[collect(1:nx+1), :] .= -1

function ggt(t)
    v = 0.01
    if t<1.0
        state = t*v*ones(sum(EBC.==-2))
    elseif t<3.0
        state = (0.02 - t*v)*ones(sum(EBC.==-2))
    end
    return state, zeros(sum(EBC.==-2))
end
gt = ggt



#pull in the y direction
NBC, fext = zeros(Int64, nnodes, ndofs), zeros(nnodes, ndofs)
NBC[collect((nx+1)*ny + 1:(nx+1)*ny + nx+1), 2] .= -1
fext[collect((nx+1)*ny + 1:(nx+1)*ny + nx+1), 2] = [2.0,3.0]*1e8



prop = Dict("name"=> testtype, "rho"=> 8000.0, "E"=> 200e+9, "nu"=> 0.45,
"sigmaY"=>0.3e+9, "K"=>1/9*200e+9, "nn"=>post_nn)

elements = []
for j = 1:ny
    for i = 1:nx 
        n = (nx+1)*(j-1) + i
        elnodes = [n, n + 1, n + 1 + (nx + 1), n + (nx + 1)]
        coords = nodes[elnodes,:]
        push!(elements,SmallStrainContinuum(coords,elnodes, prop,2))
    end
end


domain = Domain(nodes, elements, ndofs, EBC, g, NBC, fext)
state = zeros(domain.neqs)
∂u = zeros(domain.neqs)
globdat = GlobalData(state,zeros(domain.neqs),
                    zeros(domain.neqs),∂u, domain.neqs, gt)

assembleMassMatrix!(globdat, domain)
updateStates!(domain, globdat)



T = 2.0
NT = 20
Δt = T/NT
for i = 1:NT
    @info i, "/" , NT
    solver = NewmarkSolver(Δt, globdat, domain, -1.0, 0.0, 1e-6, 10)
    
end
error()


nntype = "nn"
H_ = Variable(diagm(0=>ones(3)))
H = H_'*H_

E = prop["E"]; ν = prop["nu"]; ρ = prop["rho"]
H0 = zeros(3,3)

H0[1,1] = E/(1. -ν*ν)
H0[1,2] = H0[1,1]*ν
H0[2,1] = H0[1,2]
H0[2,2] = H0[1,1]
H0[3,3] = E/(2.0*(1.0+ν))

H0 /= 1e11

# H = Variable(H0.+1)
# H = H0



W1 = Variable(rand(9,3))
b1 = Variable(rand(3))
W2 = Variable(rand(3,3))
b2 = Variable(rand(3))
W3 = Variable(rand(3,1))
b3 = Variable(rand(1))

_W1 = Variable(rand(9,3))
_b1 = Variable(rand(3))
_W2 = Variable(rand(3,3))
_b2 = Variable(rand(3))
_W3 = Variable(rand(3,3))
_b3 = Variable(rand(3))


function nn(ε, ε0, σ0)
    local y, y1, y2, y3
    if nntype=="linear"
        y = ε*H*1e11
        # op1 = tf.print("* ", ε,summarize=-1)
        # y = bind(y, op1)
        # op2 = tf.print("& ", y, summarize=-1)
        # y = bind(y, op2)
        y
    elseif nntype=="nn"
        x = [ε*1e11 ε0*1e11 σ0]
        # x = ε
        # y = ae(x, [20,3], "nn")*1e11
        y1 = x*W1+b1
        y2 = tanh(y1)
        y2 = y2*W2+b2
        y3 = tanh(y2)
        y3 = sigmoid(y3*W3+b3)
        # i = cast(squeeze(y3)>0.5, Float64)
        i = squeeze(y3)
        i = [i i i]

        y1 = x*_W1+_b1
        y2 = tanh(y1)
        y2 = y2*_W2+_b2
        y3 = tanh(y2)
        y3 = y3*_W3+_b3
        i .* (σ0 + (ε-ε0)*H0*1e11) + (1-i) .* (y1+y2+y3)
        
    end
    # op = tf.print(σ0)
    # y = bind(y, op)
    
end


#F = zeros(domain.neqs, NT+1)
F = repeat(domain.fext, 1, NT+1)
Ftot, E_all = preprocessing(domain, globdat, F, Δt)
# Fext = [-1.83823521926099986423 1.83823521926099897605 -10.41666612582739404047 -10.41666612582739404047
# -0.00000014971328692826 0.00000014971329137836 -0.00000108167848899163 -0.00000108167849091910
# 0.00000007485663168454 -0.00000007485663374036 0.00000054083913203309 0.00000054083913738728
# 0.00000000000001074496 -0.00000000000001156994 0.00000000000011383182 0.00000000000011433157
# -0.00000000000000317019 0.00000000000000129020 -0.00000000000002433776 -0.00000000000003840134]*2

# @info "Fext ", Fext
loss = DynamicMatLawLoss(domain, E_all, Ftot, nn)
sess = Session(); init(sess)
@show run(sess, loss)
BFGS(sess, loss)
println("Real H = ", H0)
run(sess, H)