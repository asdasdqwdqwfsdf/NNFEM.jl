using Revise
using NNFEM
using PoreFlow

using ADCME
using PyCall
using LinearAlgebra
using PyPlot
using Random
# Random.seed!(233)

function small_continuum_strain(state)
    small_continuum_strain_ = load_op_and_grad("./build/libSmallContinuumStrain","small_continuum_strain")
    state = convert_to_tensor([state], [Float64]); state = state[1]
    small_continuum_strain_(state)
end

m = 10
n = 10
h = 0.1
domain = example_domain(m, n, h)
init_nnfem(domain)
# TODO: specify your input parameters
state = rand(domain.nnodes*2)
u = small_continuum_strain(state)
sess = Session(); init(sess)
@show maximum(abs.(run(sess, u)-eval_strain_on_gauss_pts(state, m, n, h)))


# uncomment it for testing gradients
# error() 


# TODO: change your test parameter to `m`
#       in the case of `multiple=true`, you also need to specify which component you are testings
# gradient check -- v
function scalar_function(m)
    return sum(small_continuum_strain(m)^2)
end

# TODO: change `m_` and `v_` to appropriate values
m_ = constant(rand(2*domain.nnodes))
v_ = rand(2*domain.nnodes)
y_ = scalar_function(m_)
dy_ = gradients(y_, m_)
ms_ = Array{Any}(undef, 5)
ys_ = Array{Any}(undef, 5)
s_ = Array{Any}(undef, 5)
w_ = Array{Any}(undef, 5)
gs_ =  @. 1 / 10^(1:5)

for i = 1:5
    g_ = gs_[i]
    ms_[i] = m_ + g_*v_
    ys_[i] = scalar_function(ms_[i])
    s_[i] = ys_[i] - y_
    w_[i] = s_[i] - g_*sum(v_.*dy_)
end

sess = Session(); init(sess)
sval_ = run(sess, s_)
wval_ = run(sess, w_)
close("all")
loglog(gs_, abs.(sval_), "*-", label="finite difference")
loglog(gs_, abs.(wval_), "+-", label="automatic differentiation")
loglog(gs_, gs_.^2 * 0.5*abs(wval_[1])/gs_[1]^2, "--",label="\$\\mathcal{O}(\\gamma^2)\$")
loglog(gs_, gs_ * 0.5*abs(sval_[1])/gs_[1], "--",label="\$\\mathcal{O}(\\gamma)\$")

plt.gca().invert_xaxis()
legend()
xlabel("\$\\gamma\$")
ylabel("Error")
